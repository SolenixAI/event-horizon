//
//  VolumeKeyTap.swift
//
//  The Mac's volume keys while the stream window is key: an active event tap on
//  system-defined events. Without Accessibility the keys work as normal.
//

import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics

/// A volume key press, as the Mac sends it.
enum VolumeKey: Equatable {
    case up, down, mute

    /// The key a system-defined media event carries (subtype 8), or nil for any other event.
    static func decode(subtype: Int, data1: Int) -> VolumeKey? {
        guard subtype == 8, (data1 & 0xFF00) >> 8 == 0xA else { return nil }
        switch (data1 & 0xFFFF_0000) >> 16 {
        case 0: return .up     // NX_KEYTYPE_SOUND_UP
        case 1: return .down   // NX_KEYTYPE_SOUND_DOWN
        case 7: return .mute   // NX_KEYTYPE_MUTE
        default: return nil
        }
    }
}

/// The Accessibility permission the volume keys need. Checking never prompts.
enum VolumeKeyAccess {
    static var isGranted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt. Nothing calls this until the first-launch onboarding ships.
    @discardableResult
    static func requestAccess() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }
}

/// The volume keys, taken from the Mac only while the stream window is key.
@MainActor
final class VolumeKeyTap {
    static let shared = VolumeKeyTap()

    /// What a volume key does to the stream. Set once by the app.
    var onKey: ((VolumeKey) -> Void)?
    private var isWanted = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    /// The stream window became key or resigned key. Keys are taken only while it is key and access is granted.
    func setStreamIsKey(_ isKey: Bool) {
        guard isKey, VolumeKeyAccess.isGranted else { disable(); return }
        if tap == nil { install() }
        isWanted = true
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Removes the tap. The stream is over, or the window is no longer key.
    func teardown() {
        disable()
        guard let tap else { return }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        source = nil
    }

    private func disable() {
        isWanted = false
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
    }

    private func install() {
        let systemDefined: CGEventMask = 1 << 14 // NX_SYSDEFINED
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: systemDefined, callback: volumeKeyCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        tap = port
        source = runLoopSource
    }

    /// Runs on the main run loop, where the tap was added. Passes every event through unless it takes a volume key.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput, let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        guard isWanted, VolumeKeyAccess.isGranted, type.rawValue == 14,
              let mediaEvent = NSEvent(cgEvent: event),
              let key = VolumeKey.decode(subtype: Int(mediaEvent.subtype.rawValue), data1: mediaEvent.data1) else {
            return Unmanaged.passUnretained(event)
        }
        onKey?(key)
        return nil
    }
}

private let volumeKeyCallback: CGEventTapCallBack = { _, type, event, refcon in
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let owner = Unmanaged<VolumeKeyTap>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated { owner.handle(type: type, event: event) }
}
