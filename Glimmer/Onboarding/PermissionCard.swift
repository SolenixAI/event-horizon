//
//  PermissionCard.swift
//
//  One optional permission: its live state, why it helps, and the one action
//  that opens its system prompt or its pane. Onboarding and Settings share it.
//

import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications

extension OnboardingItem {
    var title: String {
        switch self {
        case .notifications: "Wake notifications"
        case .controllerButtons: "Controller extra buttons"
        case .volumeKeys: "Volume keys"
        case .wifiHelper: "Wi-Fi helper"
        case .openAtLogin: "Open at login"
        }
    }

    var symbol: String {
        switch self {
        case .notifications: "bell.badge"
        case .controllerButtons: "gamecontroller"
        case .volumeKeys: "speaker.wave.2"
        case .wifiHelper: "wifi"
        case .openAtLogin: "power"
        }
    }

    @MainActor var explanation: String {
        switch self {
        case .notifications:
            "Event Horizon can tell you when your PC is awake, if you are in another app. macOS asks next."
        case .controllerButtons:
            AppModel.rawHIDExplanation
        case .volumeKeys:
            "Allow Accessibility so your Mac's volume keys control the game while you play. macOS asks next."
        case .wifiHelper:
            AWDLEnablePrompt.explanation + " " + AWDLEnablePrompt.installNote
        case .openAtLogin:
            "Open Event Horizon when you log in. It is off by default; the switch above turns it on."
        }
    }
}

struct PermissionCard: View {
    @Environment(AppModel.self) private var model
    let item: OnboardingItem
    let state: OnboardingItemState
    /// Called after an action the OS answers later, so the rail reads again.
    var onChanged: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(item.title).font(.headline)
                    Spacer(minLength: 8)
                    Text(state.label)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(item.title): \(state.label)")
                }
                Text(item.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actions
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    @ViewBuilder private var actions: some View {
        if let action = primaryAction {
            Button(action.label, action: action.run)
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("\(action.label), \(item.title)")
                .padding(.top, 2)
        }
    }

    /// The one action a state offers: a pre-alert "Continue" while the choice is
    /// open, a pane link once it is refused, and nothing once it is settled.
    private var primaryAction: (label: String, run: () -> Void)? {
        switch (item, state) {
        case (.notifications, .waiting): ("Continue", requestNotifications)
        case (.notifications, .off): ("Open Settings", Self.openNotifications)
        case (.controllerButtons, .waiting): ("Continue", allowControllerButtons)
        case (.controllerButtons, .off): ("Open Settings", RawHIDControl.openInputMonitoring)
        case (.volumeKeys, .waiting): ("Continue", allowVolumeKeys)
        case (.volumeKeys, .off): ("Open Settings", Self.openAccessibility)
        case (.wifiHelper, .off): ("Continue", enableWiFi)
        case (.wifiHelper, .needsApproval), (.openAtLogin, .needsApproval):
            ("Open Login Items", { SMAppService.openSystemSettingsLoginItems() })
        default: nil
        }
    }

    private func requestNotifications() {
        Task { @MainActor in
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            onChanged()
        }
    }

    /// The explanation on the card is the pre-alert. The request runs off the main thread.
    private func allowControllerButtons() {
        model.rawHIDControllerEnabled = true
        RawHIDControl.registerAndOpen()
    }

    /// The rail reads again when the app returns from the prompt, so the card stays Waiting until macOS answers.
    private func allowVolumeKeys() {
        UserDefaults.standard.set(true, forKey: LiveOnboardingSource.accessibilityAskedKey)
        VolumeKeyAccess.requestAccess()
    }

    /// Registration settles on the main actor a moment after `enable()`, so read again then.
    private func enableWiFi() {
        AWDLHelperManager.shared.enable()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            onChanged()
        }
    }

    private static func openNotifications() {
        openPane("x-apple.systempreferences:com.apple.preference.notifications")
    }

    private static func openAccessibility() {
        openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    private static func openPane(_ address: String) {
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}

/// The rail of optional items, read from the OS on every appearance and every
/// return to the app. Onboarding lets the person skip a card; Settings does not.
struct PermissionRail: View {
    var skippable = false
    /// Settings lists open at login too; the first-launch pass does not.
    var includesLoginItem = false
    @State private var states: [OnboardingItem: OnboardingItemState] = [:]
    @State private var skipped: Set<OnboardingItem> = []
    private let returned = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleItems, id: \.self) { item in
                if let state = states[item] {
                    if skipped.contains(item) {
                        Text("\(item.title): not now. You can turn it on later in Settings.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .trailing, spacing: 4) {
                            PermissionCard(item: item, state: state, onChanged: reload)
                            if skippable, state == .waiting || state == .off {
                                Button("Not now") { skipped.insert(item) }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Not now, \(item.title)")
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task { await readStates() }
        .onReceive(returned) { _ in reload() }
    }

    private var visibleItems: [OnboardingItem] {
        OnboardingItem.allCases.filter { includesLoginItem || $0 != .openAtLogin }
    }

    private func reload() {
        Task { await readStates() }
    }

    private func readStates() async {
        states = await OnboardingRail.read(LiveOnboardingSource())
    }
}
