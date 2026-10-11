import Foundation
import Testing
@testable import Glimmer

/// A PC that no longer knows this Mac opens the pair step for it at once, and the
/// stream the user asked for is the one offered after Allow.
struct ForgottenMacRepairTests {
    static let den = Host(id: "pc-1", name: "den", customName: "Den PC", localAddress: "192.0.2.10",
                          manualAddress: nil, apps: [], lastConnected: nil, serverCertPEM: nil,
                          appVersion: nil, macAddress: nil)
    static let game = LibraryApp(id: 42, name: "Dragonwilds", hdr: false, hidden: false)

    @MainActor @Test func aPairingFailureOpensThePairStepForThatPc() {
        let model = AppModel()
        model.hosts = [Self.den]
        model.lastLaunchAttempt = (Self.game, Self.den)

        model.showStreamFailure(("Den PC no longer recognizes this Mac.", .pairing), on: Self.den)

        #expect(model.pairSheetShown)
        #expect(model.pairSheetHost?.id == "pc-1")
        #expect(model.streamAfterPairing?.app == Self.game)
    }

    @MainActor @Test func otherFailuresKeepTheBannerOnly() {
        let model = AppModel()
        model.showStreamFailure((AppModel.unreachableMessage("Den PC"), .unreachable), on: Self.den)

        #expect(!model.pairSheetShown)
        #expect(model.nativeStreamError == AppModel.unreachableMessage("Den PC"))
    }

    @MainActor @Test func pairingThatPcClearsItsErrorAndKeepsTheWaitingStream() {
        let model = AppModel()
        model.hosts = [Self.den]
        model.lastLaunchAttempt = (Self.game, Self.den)
        model.showStreamFailure(("Den PC no longer recognizes this Mac.", .pairing), on: Self.den)

        model.pairingSucceeded(hostID: "pc-1")

        #expect(model.nativeStreamError == nil)
        #expect(model.streamAfterPairing?.app == Self.game)
    }

    @MainActor @Test func aWaitingStreamForAnotherPcIsNotOffered() {
        let model = AppModel()
        let tower = Host(id: "pc-2", name: "tower", customName: nil, localAddress: "192.0.2.20",
                         manualAddress: nil, apps: [], lastConnected: nil, serverCertPEM: nil,
                         appVersion: nil, macAddress: nil)
        model.lastLaunchAttempt = (Self.game, tower)

        model.showStreamFailure(("Den PC no longer recognizes this Mac.", .pairing), on: Self.den)

        #expect(model.streamAfterPairing == nil)
    }
}
