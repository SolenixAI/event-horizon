//
//  OnboardingLiveSource.swift
//
//  Reads the real OS state for the rail. Each read asks the system; nothing is cached here.
//

import GameController
import IOKit.hid
import Security
import UserNotifications

@MainActor
struct LiveOnboardingSource: OnboardingOSSource {
    /// Set once the Accessibility card has shown its system prompt.
    static let accessibilityAskedKey = "volumeKeysAccessibilityAsked"

    func notificationGrant() async -> NotificationGrant {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined { return .notAsked }
        return WakeNotifier.shows(settings.authorizationStatus, style: settings.alertStyle) ? .allowed : .denied
    }

    var inputAccess: InputAccess {
        if DualSenseHID.shared.reportCount > 0 { return .granted }
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return .granted
        case kIOHIDAccessTypeDenied: return .denied
        default: return .unknown
        }
    }

    var accessibilityTrusted: Bool { VolumeKeyAccess.isGranted }

    var accessibilityAsked: Bool {
        UserDefaults.standard.bool(forKey: Self.accessibilityAskedKey)
    }

    var dualSenseConnected: Bool {
        GCController.controllers().contains { $0.productCategory == GCProductCategoryDualSense }
    }

    var helper: HelperRegistration {
        switch AWDLHelperManager.shared.state {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .unavailable: return .unavailable
        }
    }

    var loginItem: HelperRegistration {
        let minimized = UserDefaults.standard.bool(forKey: "launchMinimized")
        switch LoginItemManager.currentStatus(minimized: minimized) {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        default: return .notRegistered
        }
    }

    /// An app with no team identifier is ad hoc signed, and the helper can't register in it.
    var buildSigned: Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code) == errSecSuccess,
              let code else { return false }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: UInt32(kSecCSSigningInformation))
        guard SecCodeCopySigningInformation(code, flags, &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return dict[kSecCodeInfoTeamIdentifier as String] != nil
    }
}
