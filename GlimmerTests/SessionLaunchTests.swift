import Foundation
import Testing
@testable import Glimmer

// Sessions construct real audio engines; keep setup from contending across these tests.
@Suite(.serialized)
struct SessionLaunchTests {
    @Test func launchOwnershipSurvivesAnUncertainResponse() {
        #expect(!StreamSession.retainsLaunchOwnership(after: StreamError.hostRefused(message: "Busy", code: 503)))
        #expect(StreamSession.retainsLaunchOwnership(after: CancellationError()))
        #expect(StreamSession.retainsLaunchOwnership(after: StreamError.hostTimedOut))
        #expect(StreamSession.retainsLaunchOwnership(after: StreamError.hostUnreachable("Connection closed")))
        #expect(StreamSession.retainsLaunchOwnership(after: StreamError.launchFailed("Malformed response")))
    }

    @Test(arguments: [false, true])
    func settledLaunchDeterminesWhetherToCancel(refused: Bool) async {
        let session = StreamSession()
        let entered = SafetyTestGate()
        let response = SafetyTestGate()
        let cancelled = SafetyTestCounter()
        let launch = Task {
            try await session.launchAndRecordOwnership(client: "client", appID: 1) {
                await entered.open()
                await response.wait()
                if refused { throw StreamError.hostRefused(message: "Busy", code: 503) }
                return Self.response
            }
        }
        await entered.wait()
        let cleanup = Task {
            await session.settlePendingLaunch { await cancelled.increment() }
        }
        await response.open()
        await cleanup.value
        _ = await launch.result
        #expect(await cancelled.value == (refused ? 0 : 1))
        #expect(await session.ownsHostSession == !refused)
        #expect(await session.hostSessionClientID == (refused ? nil : "client"))
    }

    @Test func cancelledConnectReturnsBeforeReplyAndLateSuccessIsCancelledAgain() async {
        let session = StreamSession()
        let entered = SafetyTestGate()
        let response = SafetyTestGate()
        let cancelled = SafetyTestCounter()
        let twice = SafetyTestGate()
        let attempt = Task {
            try await StreamAttempt.run(until: Date().addingTimeInterval(30)) {
                try await session.launchAndRecordOwnership(client: "client", appID: 1) {
                    await entered.open()
                    await response.wait()
                    try Task.checkCancellation()
                    return Self.response
                }
            }
        }
        await entered.wait()
        attempt.cancel()
        let cancelledPromptly = await TerminationGate.runBounded(seconds: 5) {
            do {
                _ = try await attempt.value
                Issue.record("Cancelled connect returned a launch response")
            } catch {
                #expect(error is CancellationError)
            }
            await session.settlePendingLaunch {
                await cancelled.increment()
                if await cancelled.value == 2 { await twice.open() }
            }
        }
        #expect(cancelledPromptly)
        #expect(await cancelled.value == 1)
        #expect(await session.ownsHostSession)
        await response.open()
        let cleaned = await TerminationGate.runBounded(seconds: 5) { await twice.wait() }
        #expect(cleaned)
        #expect(await cancelled.value == 2)
    }

    @Test func lateSuccessLeavesAReconnectAlone() async {
        let session = StreamSession()
        let entered = SafetyTestGate()
        let response = SafetyTestGate()
        let cancelled = SafetyTestCounter()
        let launch = Task {
            try await session.launchAndRecordOwnership(client: "client", appID: 1) {
                await entered.open()
                await response.wait()
                return Self.response
            }
        }
        await entered.wait()
        await session.settlePendingLaunch { await cancelled.increment() }
        #expect(await cancelled.value == 1)
        // The user reconnects to the same PC before the abandoned /launch replies.
        let reconnect = StreamSession()
        _ = try? await reconnect.launchAndRecordOwnership(client: "client", appID: 1) { Self.response }
        await response.open()
        _ = await launch.result
        // Without the newer-launch check, the late cancel lands within milliseconds.
        let cancelledAgain = await TerminationGate.runBounded(seconds: 0.5) {
            while await cancelled.value < 2, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(!cancelledAgain)
        #expect(await cancelled.value == 1)
    }

    /// A launch on another PC doesn't stand in for this one: the abandoned launch's late success
    /// still gets its second /cancel, so the first PC isn't left running the game.
    @Test func lateSuccessIsCancelledWhenAnotherPcLaunches() async {
        let session = StreamSession()
        await session.useServer(ServerInfo(address: "192.0.2.1", uniqueId: "pc-a", serverName: "Den PC"))
        let entered = SafetyTestGate()
        let response = SafetyTestGate()
        let cancelled = SafetyTestCounter()
        let launch = Task {
            try await session.launchAndRecordOwnership(client: "client", appID: 1) {
                await entered.open()
                await response.wait()
                return Self.response
            }
        }
        await entered.wait()
        await session.settlePendingLaunch { await cancelled.increment() }
        let other = StreamSession()
        await other.useServer(ServerInfo(address: "192.0.2.2", uniqueId: "pc-b", serverName: "Tower"))
        _ = try? await other.launchAndRecordOwnership(client: "client", appID: 1) { Self.response }
        await response.open()
        _ = await launch.result
        let cancelledAgain = await TerminationGate.runBounded(seconds: 2) {
            while await cancelled.value < 2, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(5)) }
        }
        #expect(cancelledAgain)
    }

    /// A pipeline's events go to the session it started for, whichever is current when they fire,
    /// so a late callback from a timed-out pipeline can't land in the next session.
    @Test func eventsGoToTheSessionTheirPipelineStartedFor() async {
        let session = StreamSession()
        let bridge = StreamBridgeContext(session: session, videoDecoder: await VideoDecoder(),
                                         audioDecoder: AudioDecoder(), inputForwarder: await InputForwarder())
        let (stream, continuation) = AsyncStream<StreamEvent>.makeStream()
        bridge.eventContinuation = continuation
        NativeConnectionEvents(bridge: bridge).stageStarting("name resolution")
        continuation.finish()
        var received = 0
        for await _ in stream { received += 1 }
        #expect(received == 1)
    }

    /// Quitting during "Reconnecting…" after an attempt failed: stop still has a client for the PC
    /// it launched on, so the owned session gets its /cancel instead of leaving the game running.
    @Test func stopCanCancelAfterAFailedReconnectAttempt() async {
        let session = StreamSession()
        await session.loseNetworkAfterReconnect(to: ServerInfo(address: "192.0.2.1", uniqueId: "pc", serverName: "Den PC"))
        let cleanup = await session.cleanupNetwork
        #expect(await cleanup?.server.uniqueId == "pc")
    }

    @Test func stopFinishesWhileLaunchRemainsPending() async {
        let session = StreamSession()
        await session.prepareLaunchTestSession()
        await session.publishLaunchTestBridge()
        let entered = SafetyTestGate()
        let response = SafetyTestGate()
        let launch = Task {
            try await session.launchAndRecordOwnership(client: "client", appID: 1) {
                await entered.open()
                await response.wait()
                return Self.response
            }
        }
        await entered.wait()
        #expect(await session.bridge != nil)
        #expect(await session.pendingLaunch != nil)
        #expect(session.terminationStopBoundSeconds == 4)
        let finished = await TerminationGate.runBounded(seconds: 5) { await session.stop() }
        #expect(finished)
        #expect(await session.pendingLaunch != nil)
        #expect(await !session.stopInProgress)
        #expect(await !session.ownsHostSession)
        await response.open()
        _ = await launch.result
    }

    @Test(arguments: [StreamError.hostTimedOut, StreamError.hostUnreachable("Connection closed")])
    func busyRecoveryKeepsOwnershipAfterTransportFailure(error: StreamError) async throws {
        let session = StreamSession()
        await session.prepareLaunchTestSession()
        var info = ServerInfo(address: "", uniqueId: "", serverName: "")
        info.currentGameID = 1
        let network = NetworkClient(server: info)
        await network.prepareLaunchTestClient()
        do {
            _ = try await session.launchAndRecordOwnership(client: "client", appID: 1) { throw error }
            Issue.record("Launch should have failed")
        } catch {
            #expect(StreamSession.retainsLaunchOwnership(after: error))
        }
        try await session.authorizeOccupancy(info, network: network, deadline: .distantFuture)
        #expect(await session.ownsHostSession)
        #expect(await session.hostSessionClientID == "client")
    }

    @Test func differentAppAfterUncertainLaunchRequiresTakeover() async throws {
        let session = StreamSession()
        await session.prepareLaunchTestSession()
        var info = ServerInfo(address: "", uniqueId: "", serverName: "")
        info.currentGameID = 2
        let network = NetworkClient(server: info)
        await network.prepareLaunchTestClient()
        _ = try? await session.launchAndRecordOwnership(client: "client", appID: 1) {
            throw StreamError.hostTimedOut
        }
        do {
            try await session.authorizeOccupancy(info, network: network, deadline: .distantFuture)
            Issue.record("A different app must require takeover")
        } catch let takeover as TakeoverRequired {
            #expect(takeover.appID == 2)
        }
        let cancelled = SafetyTestCounter()
        await session.settlePendingLaunch { await cancelled.increment() }
        #expect(await cancelled.value == 0)
        #expect(await !session.ownsHostSession)
    }

    @Test(arguments: [false, true])
    func olderLaunchCannotClearNewerLaunch(refused: Bool) async throws {
        let session = StreamSession()
        let firstEntered = SafetyTestGate()
        let firstResponse = SafetyTestGate()
        let secondEntered = SafetyTestGate()
        let secondResponse = SafetyTestGate()
        let first = Task {
            try await session.launchAndRecordOwnership(client: "first", appID: 1) {
                await firstEntered.open()
                await firstResponse.wait()
                if refused { throw StreamError.hostRefused(message: "Busy", code: 503) }
                return Self.response
            }
        }
        await firstEntered.wait()
        let second = Task {
            try await session.launchAndRecordOwnership(client: "second", appID: 1) {
                await secondEntered.open()
                await secondResponse.wait()
                return Self.response
            }
        }
        await secondEntered.wait()
        let pending = await session.pendingLaunch
        await firstResponse.open()
        _ = await first.result
        #expect(pending != nil)
        #expect(await session.pendingLaunch == pending)
        #expect(await session.ownsHostSession)
        #expect(await session.hostSessionClientID == "second")
        #expect(await session.hostSessionAppID == 1)
        await secondResponse.open()
        _ = try await second.value
        #expect(await session.pendingLaunch == nil)
    }

    /// A Home click on a PC that runs a game resumes it (/resume) and never cancels it. The rule is
    /// the click's: the desk takes whatever runs, the cover resumes only its own app, and a different
    /// shelf game replaces what runs, as it always has.
    @Test func homeClicksResumeTheRunningGameAndNeverCancelIt() {
        struct HomeClick {
            let rule: ResumeRule
            let appID: Int
            let runningID: Int
            let step: LaunchStep
        }
        let cases = [
            HomeClick(rule: .anyApp, appID: 1, runningID: 7, step: .resume),
            HomeClick(rule: .anyApp, appID: 1, runningID: 0, step: .launch),
            HomeClick(rule: .sameApp, appID: 7, runningID: 7, step: .resume),
            HomeClick(rule: .sameApp, appID: 7, runningID: 0, step: .launch),
            HomeClick(rule: .sameApp, appID: 7, runningID: 9, step: .cancelThenLaunch),
            HomeClick(rule: .never, appID: 7, runningID: 7, step: .cancelThenLaunch),
            HomeClick(rule: .never, appID: 7, runningID: 0, step: .launch)
        ]
        for item in cases {
            let step = StreamAttempt.launchStep(
                rule: item.rule, appID: item.appID, runningID: item.runningID, busy: item.runningID != 0)
            #expect(step == item.step, "\(item.rule) for app \(item.appID) on a PC running \(item.runningID)")
        }
        // A busy PC with no game named still gets the takeover path, as before.
        #expect(StreamAttempt.launchStep(rule: .never, appID: 7, runningID: 0, busy: true) == .cancelThenLaunch)
    }

    /// The desk click opens the game the PC runs; on an idle PC it opens the Desktop, as before.
    @MainActor @Test func aDeskClickTargetsTheGameThePCIsRunning() {
        let desktop = LibraryApp(id: 1, name: "Desktop", hdr: false, hidden: false)
        let game = LibraryApp(id: 7, name: "Hades", hdr: false, hidden: false)
        let pc = Host(id: "pc-1", name: "den", customName: "Den PC", localAddress: "192.0.2.10", manualAddress: nil,
                      apps: [desktop, game], lastConnected: nil, serverCertPEM: nil, appVersion: nil, macAddress: nil)
        let model = AppModel()
        model.hosts = [pc]
        #expect(model.deskTarget(of: pc) == desktop)
        model.hostLiveStatus = HostLiveStatus(
            hostID: pc.id, state: .streamingApp(name: "Hades"), rttMs: 3, sunshineVersion: nil, capturedAt: Date())
        #expect(model.deskTarget(of: pc) == game)
    }

    /// A cover click resumes only the app already on the PC's screen. Any other cover is a plain
    /// open, which replaces a game that runs (the shelf's switch, as before).
    @MainActor @Test func aCoverClickResumesOnlyTheAppOnTheScreen() {
        let game = LibraryApp(id: 7, name: "Hades", hdr: false, hidden: false)
        let other = LibraryApp(id: 9, name: "Celeste", hdr: false, hidden: false)
        let pc = Host(id: "pc-1", name: "den", customName: "Den PC", localAddress: "192.0.2.10", manualAddress: nil,
                      apps: [game, other], lastConnected: nil, serverCertPEM: nil, appVersion: nil, macAddress: nil)
        let model = AppModel()
        model.hosts = [pc]
        model.hostLiveStatus = HostLiveStatus(
            hostID: pc.id, state: .streamingApp(name: "Hades"), rttMs: 3, sunshineVersion: nil, capturedAt: Date())
        #expect(model.shelfRule(for: game, on: pc) == .sameApp)
        #expect(model.shelfRule(for: other, on: pc) == .never)
        model.hostLiveStatus = nil
        #expect(model.shelfRule(for: game, on: pc) == .never)
    }

    private static var response: LaunchResponse {
        LaunchResponse(sessionURL: "", gcmKey: Data(), gcmKeyId: Data())
    }
}

private extension StreamSession {
    func prepareLaunchTestSession() { isStreaming = true }

    func useServer(_ server: ServerInfo) { reconnectServer = server }

    func loseNetworkAfterReconnect(to server: ServerInfo) {
        reconnectServer = server
        network = nil
    }

    func publishLaunchTestBridge() async {
        let decoder = await VideoDecoder()
        let forwarder = await InputForwarder()
        bridge = StreamBridgeContext(session: self, videoDecoder: decoder,
                                     audioDecoder: audioDecoder, inputForwarder: forwarder)
    }
}

private extension NetworkClient {
    func prepareLaunchTestClient() { clientUniqueID = "client" }
}
