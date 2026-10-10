#if canImport(Sparkle)
import Sparkle
import SwiftUI

/// Owns the Sparkle updater for the app's lifetime. `SPUStandardUpdaterController`
/// wires the standard user driver (the "update available" panel) and starts the
/// daily check at launch. One shared instance, reached from the app-menu command.
///
/// The whole file is gated on `canImport(Sparkle)` so Event Horizon still builds before
/// the Sparkle SPM package is linked. Info.plist is the one source of truth for the
/// feed (SUFeedURL), the key (SUPublicEDKey) and the schedule and install policy.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController
    /// Retained here: Sparkle holds its user driver delegate weakly.
    private let streamAwareAlerts = StreamAwareUpdateAlerts(
        isStreaming: { AppDelegate.boundManager?.isStreaming ?? false },
        showUpdate: { UpdaterController.shared.updater.checkForUpdates() },
        checkInBackground: { UpdaterController.shared.updater.checkForUpdatesInBackground() })

    private init() {
        // Starts at launch. Sparkle offers an update only when the appcast's build
        // number is strictly greater than the running build's.
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: streamAwareAlerts, userDriverDelegate: streamAwareAlerts)
        streamAwareAlerts.observeAvailability(of: controller.updater)
    }

    var updater: SPUUpdater { controller.updater }
}

/// Defers daily checks and update alerts so neither downloads nor pulls focus
/// during a stream. User-initiated checks pass through.
@MainActor
final class StreamAwareUpdateAlerts: NSObject, @preconcurrency SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private let isStreaming: @MainActor () -> Bool
    private let showUpdate: @MainActor () -> Void
    private let checkInBackground: @MainActor () -> Void
    private(set) var isHoldingUpdate = false
    private var hasPendingBackgroundCheck = false
    private(set) var canCheckForUpdates = true
    private var availabilityObservation: NSKeyValueObservation?

    init(
        isStreaming: @escaping @MainActor () -> Bool,
        showUpdate: @escaping @MainActor () -> Void,
        checkInBackground: @escaping @MainActor () -> Void
    ) {
        self.isStreaming = isStreaming
        self.showUpdate = showUpdate
        self.checkInBackground = checkInBackground
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        try mayPerform(updateCheck)
    }

    func observeAvailability(of updater: SPUUpdater) {
        availabilityObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.availabilityDidChange(updater.canCheckForUpdates)
            }
        }
    }

    func availabilityDidChange(_ canCheck: Bool) {
        canCheckForUpdates = canCheck
        // Sparkle can report availability before its scheduling callback ends.
        Task { @MainActor [weak self] in
            self?.runPendingActionsWhenStreamEnds()
        }
    }

    func mayPerform(_ updateCheck: SPUUpdateCheck) throws {
        if updateCheck == .updates {
            hasPendingBackgroundCheck = false
            return
        }
        guard updateCheck == .updatesInBackground, isStreaming() else { return }
        hasPendingBackgroundCheck = true
        runPendingActionsWhenStreamEnds()
        throw NSError(domain: "StreamAwareUpdateAlerts", code: 1)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        UpdatePolicy.mayShowWindow(isStreaming: isStreaming())
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if !handleShowingUpdate { holdUntilStreamEnds() }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        isHoldingUpdate = false
    }

    func holdUntilStreamEnds() {
        Diag.info("update alert held until the stream ends", "Update")
        isHoldingUpdate = true
        runPendingActionsWhenStreamEnds()
    }

    private func runPendingActionsWhenStreamEnds() {
        guard isHoldingUpdate || hasPendingBackgroundCheck else { return }
        guard isStreaming() else {
            runPendingActions()
            return
        }
        // onChange fires before the new value lands; re-read it on the next turn.
        withObservationTracking { _ = isStreaming() } onChange: { [weak self] in
            Task { @MainActor in self?.runPendingActionsWhenStreamEnds() }
        }
    }

    private func runPendingActions() {
        if isHoldingUpdate {
            isHoldingUpdate = false
            showUpdate()
        }
        if hasPendingBackgroundCheck {
            guard !isStreaming(), canCheckForUpdates else { return }
            hasPendingBackgroundCheck = false
            checkInBackground()
        }
    }
}

/// Tracks Sparkle's KVO-observable `canCheckForUpdates` as Observation-tracked
/// state so the menu command can grey out while a check is already running.
/// Modern Observation + `NSKeyValueObservation` - no Combine, matching the app's
/// `@Observable` model style.
@MainActor
@Observable
final class UpdateAvailability {
    private(set) var canCheckForUpdates = false
    @ObservationIgnored private var observation: NSKeyValueObservation?

    init(_ updater: SPUUpdater) {
        observation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            // Sparkle posts this KVO change on the main thread; assert it so the
            // @MainActor reads/writes are isolation-clean without a Task hop.
            MainActor.assumeIsolated { self?.canCheckForUpdates = updater.canCheckForUpdates }
        }
    }
}

/// The "Check for Updates…" menu command. Greys out mid-check, and mid-stream too,
/// because `UpdatePolicy` keeps update windows off a live stream.
struct CheckForUpdatesView: View {
    private let updater: SPUUpdater
    private let model: AppModel
    @State private var availability: UpdateAvailability

    init(updater: SPUUpdater, model: AppModel) {
        self.updater = updater
        self.model = model
        _availability = State(initialValue: UpdateAvailability(updater))
    }

    var body: some View {
        Button("Check for Updates…") { updater.checkForUpdates() }
            .disabled(!availability.canCheckForUpdates || !UpdatePolicy.mayCheckNow(isStreaming: model.isStreaming))
    }
}
#endif
