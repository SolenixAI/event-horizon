//
//  PointerPolicyTests.swift
//
//  Who owns the pointer: the PC's Desktop keeps the cursor free and absolute,
//  every other app locks it while the stream is in front. Pure rules plus the
//  forwarder's gates, none of which may touch the real cursor.
//

import AppKit
import Testing
@testable import Glimmer

struct PointerPolicyForAppTests {

    @Test func desktopIsFreeInAnyCaseAndPadding() {
        for name in ["Desktop", "desktop", "DESKTOP", "  Desktop  ", "Desktop\n", "Steam Big Picture", "Old School RuneScape"] {
            #expect(PointerPolicy.forApp(named: name) == .free, "\(name.debugDescription)")
        }
    }

    @Test func everyOtherAppLocks() {
        for name in ["ARC Raiders", "Path of Exile 2", "Remote Desktop", "Desktop 2", "", "  "] {
            #expect(PointerPolicy.forApp(named: name) == .lock, "\(name.debugDescription)")
        }
    }

    @Test func aStreamLocksUnlessToldOtherwise() {
        #expect(StreamConfig(width: 2560, height: 1600, fps: 60, bitrateKbps: 80_000).pointerPolicy == .lock)
    }
}

@MainActor
struct PointerPolicyForwarderTests {

    /// A window that is never shown: not key, and on no Space.
    private func hiddenWindow() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 64, height: 64),
                 styleMask: .borderless, backing: .buffered, defer: true)
    }

    @Test func freeNeverCapturesAndKeepsTheCoalescingAlone() {
        let forwarder = InputForwarder()
        forwarder.pointerPolicy = .free
        forwarder.enterCapturedMode()
        #expect(!forwarder.isMouseCaptured)
        #expect(forwarder.savedMouseCoalescing == nil)
    }

    @Test func freeIgnoresTheHoverGrabAndTheChord() {
        let forwarder = InputForwarder()
        forwarder.pointerPolicy = .free
        forwarder.isWindowMode = true
        forwarder.notePointerEnteredStreamView()
        forwarder.capturePointer(reason: "test")
        forwarder.togglePointerCapture(reason: "test")
        #expect(!forwarder.isMouseCaptured)
    }

    @Test func absolutePointerFollowsThePolicy() {
        let forwarder = InputForwarder()
        forwarder.pointerPolicy = .free
        #expect(forwarder.usesAbsolutePointer)
        #expect(forwarder.sendsAbsolutePointer)
        forwarder.pointerPolicy = .lock
        #expect(!forwarder.usesAbsolutePointer)
        forwarder.isWindowMode = true
        #expect(forwarder.usesAbsolutePointer)
        forwarder.isMouseCaptured = true
        #expect(!forwarder.usesAbsolutePointer)
    }

    @Test func lockedPointerIsFreedWhenTheWindowIsOffTheActiveSpace() {
        let forwarder = InputForwarder()
        let window = hiddenWindow()
        forwarder.window = window
        forwarder.installFocusObservers(for: window)
        defer { forwarder.removeFocusObservers() }
        forwarder.isMouseCaptured = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // The observer runs on the main queue.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(!window.isOnActiveSpace)
        #expect(!forwarder.isMouseCaptured)
    }

    @Test func freeInstallsNoSpaceObserver() {
        let forwarder = InputForwarder()
        forwarder.pointerPolicy = .free
        let window = hiddenWindow()
        forwarder.installFocusObservers(for: window)
        defer { forwarder.removeFocusObservers() }
        #expect(forwarder.activeSpaceObserver == nil)
    }

    @Test func removingTheFocusObserversRemovesTheSpaceObserver() {
        let forwarder = InputForwarder()
        forwarder.installFocusObservers(for: hiddenWindow())
        #expect(forwarder.activeSpaceObserver != nil)
        forwarder.removeFocusObservers()
        #expect(forwarder.activeSpaceObserver == nil)
    }
}
