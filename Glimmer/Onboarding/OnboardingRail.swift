//
//  OnboardingRail.swift
//
//  The optional permissions as live state. Every visit reads the OS again;
//  nothing is stored, so a grant or revoke in System Settings shows at once.
//

import Foundation

enum OnboardingItem: CaseIterable, Sendable {
    case notifications, controllerButtons, volumeKeys, wifiHelper
    /// Settings only: the first-launch pass does not offer it, since it is off by default.
    case openAtLogin
}

enum OnboardingItemState: Equatable, Sendable {
    case allowed, waiting, off, needsApproval, notInThisBuild

    var label: String {
        switch self {
        case .allowed: "Allowed"
        case .waiting: "Waiting"
        case .off: "Off"
        case .needsApproval: "Needs approval"
        case .notInThisBuild: "Not in this build"
        }
    }
}

/// Raw answers from the OS, reduced to what the rail needs.
enum NotificationGrant: Sendable { case notAsked, allowed, denied }
enum InputAccess: Sendable { case unknown, granted, denied }
enum HelperRegistration: Sendable { case notRegistered, requiresApproval, enabled, unavailable }

/// The OS sources the rail reads. The live one reads the system; tests pass fakes.
@MainActor
protocol OnboardingOSSource {
    func notificationGrant() async -> NotificationGrant
    var inputAccess: InputAccess { get }
    var accessibilityTrusted: Bool { get }
    var accessibilityAsked: Bool { get }
    /// A DualSense is attached, so the extra-buttons item applies.
    var dualSenseConnected: Bool { get }
    var helper: HelperRegistration { get }
    /// The build carries a team identifier, so the Wi-Fi helper can register.
    var buildSigned: Bool { get }
    /// The registration of the open-at-login item, read from macOS.
    var loginItem: HelperRegistration { get }
}

enum OnboardingRail {
    /// Every item that applies right now. Controller buttons appear only while a
    /// DualSense is attached.
    @MainActor static func read(_ source: any OnboardingOSSource) async -> [OnboardingItem: OnboardingItemState] {
        var states: [OnboardingItem: OnboardingItemState] = [:]
        states[.notifications] = notifications(await source.notificationGrant())
        if source.dualSenseConnected { states[.controllerButtons] = controllerButtons(source.inputAccess) }
        states[.volumeKeys] = volumeKeys(trusted: source.accessibilityTrusted, asked: source.accessibilityAsked)
        states[.wifiHelper] = wifiHelper(source.helper, signed: source.buildSigned)
        states[.openAtLogin] = openAtLogin(source.loginItem)
        return states
    }

    /// Open at login needs an action only while macOS waits for approval in Login Items.
    static func openAtLogin(_ registration: HelperRegistration) -> OnboardingItemState {
        switch registration {
        case .enabled: .allowed
        case .requiresApproval: .needsApproval
        case .notRegistered, .unavailable: .off
        }
    }

    static func notifications(_ grant: NotificationGrant) -> OnboardingItemState {
        switch grant {
        case .notAsked: .waiting
        case .allowed: .allowed
        case .denied: .off
        }
    }

    static func controllerButtons(_ access: InputAccess) -> OnboardingItemState {
        switch access {
        case .unknown: .waiting
        case .granted: .allowed
        case .denied: .off
        }
    }

    /// Accessibility can't say "never asked" apart from "refused", so the card
    /// remembers that it asked: after that, a missing grant reads Off.
    static func volumeKeys(trusted: Bool, asked: Bool) -> OnboardingItemState {
        if trusted { return .allowed }
        return asked ? .off : .waiting
    }

    static func wifiHelper(_ helper: HelperRegistration, signed: Bool) -> OnboardingItemState {
        guard signed else { return .notInThisBuild }
        switch helper {
        case .enabled: return .allowed
        case .requiresApproval: return .needsApproval
        case .notRegistered, .unavailable: return .off
        }
    }
}
