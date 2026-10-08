//
//  CommandTranslateTests.swift
//
//  Mac shortcuts on the PC's Desktop: the table, what refuses, and the exact
//  four events a translated chord puts on the wire.
//

import AppKit
import Carbon.HIToolbox
import Testing
import os
@testable import Glimmer

private struct KeySend: Equatable {
    let code: Int16
    let action: Int8
    let modifiers: Int8
}

private final class KeyRecordingBackend: StreamingBackend {
    private let sent = OSAllocatedUnfairLock(initialState: [KeySend]())

    var keys: [KeySend] { sent.withLock { $0 } }

    func startConnection(server: BackendServerInfo, config: BackendStreamConfig) throws {}
    func stopConnection() {}
    func interruptConnection() {}
    func attachVideoSink(_ sink: VideoSink) {}
    func attachAudioSink(_ sink: NativeAudioSink) {}
    func estimatedRtt() -> (rttMs: Double, varianceMs: Double)? { nil }
    func requestIdrFrame() {}
    func hdrMetadata() -> HdrMetadata? { nil }
    func launchUrlQueryParameters() -> String { "" }
    func stageName(for stage: Int32) -> String { "" }
    func sendKeyboard(keyCode: Int16, action: Int8, modifiers: Int8, flags: Int8) -> Int32 {
        sent.withLock { $0.append(KeySend(code: keyCode, action: action, modifiers: modifiers)) }
        return 0
    }
    func sendMouseMove(dx: Int16, dy: Int16) -> Int32 { 0 }
    func sendMousePosition(x: Int16, y: Int16, refW: Int16, refH: Int16) -> Int32 { 0 }
    func sendMouseButton(action: Int8, button: Int32) -> Int32 { 0 }
    func sendScroll(_ amount: Int16) -> Int32 { 0 }
    func sendHScroll(_ amount: Int16) -> Int32 { 0 }
    func sendMultiController(num: Int16, mask: Int16, buttons: Int32, analog: GamepadAnalog) -> Int32 { 0 }
    func sendControllerArrival(
        num: UInt8, mask: UInt16, type: UInt8,
        supportedButtons: UInt32, caps: UInt16
    ) -> Int32 { 0 }
    func sendControllerTouch(
        num: UInt8, eventType: UInt8, touchpadIndex: UInt8,
        pointerId: UInt32, x: Float, y: Float, pressure: Float
    ) -> Int32 { 0 }
    func sendControllerMotion(
        num: UInt8, motionType: UInt8, x: Float, y: Float, z: Float
    ) -> Int32 { 0 }
    func sendUtf8Text(_ text: String) -> Int32 { 0 }
}

private func keyEvent(_ keyCode: Int, _ chars: String, mods: NSEvent.ModifierFlags,
                      type: NSEvent.EventType = .keyDown, isRepeat: Bool = false) throws -> NSEvent {
    try #require(NSEvent.keyEvent(
        with: type, location: .zero, modifierFlags: mods, timestamp: 1,
        windowNumber: 0, context: nil, characters: chars, charactersIgnoringModifiers: chars,
        isARepeat: isRepeat, keyCode: UInt16(keyCode)))
}

struct CommandTranslationTableTests {

    private let table: [(key: String, code: Int, vk: Int16)] = [
        ("c", kVK_ANSI_C, 0x43), ("v", kVK_ANSI_V, 0x56), ("x", kVK_ANSI_X, 0x58),
        ("z", kVK_ANSI_Z, 0x5A), ("a", kVK_ANSI_A, 0x41), ("s", kVK_ANSI_S, 0x53),
        ("f", kVK_ANSI_F, 0x46), ("t", kVK_ANSI_T, 0x54), ("w", kVK_ANSI_W, 0x57)
    ]

    @Test func nineShortcutsBecomeTheirCtrlTwin() {
        #expect(CommandTranslation.letters.count == 9)
        for row in table {
            #expect(CommandTranslation.ctrlKey(typed: row.key, keyCode: row.code, modifiers: [.command],
                                               policy: .free) == row.vk, "⌘\(row.key)")
        }
    }

    @Test func shiftPassesAndCapsLockDoesNotMatter() {
        for row in table {
            #expect(CommandTranslation.ctrlKey(typed: row.key.uppercased(), keyCode: row.code,
                                               modifiers: [.command, .shift], policy: .free) == row.vk)
            #expect(CommandTranslation.ctrlKey(typed: row.key, keyCode: row.code,
                                               modifiers: [.command, .capsLock], policy: .free) == row.vk)
        }
    }

    @Test func controlOptionAndMissingCommandRefuse() {
        for mods: NSEvent.ModifierFlags in [[.command, .control], [.command, .option],
                                            [.command, .shift, .control], [], [.shift], [.control]] {
            #expect(CommandTranslation.ctrlKey(typed: "c", keyCode: kVK_ANSI_C, modifiers: mods,
                                               policy: .free) == nil)
        }
    }

    @Test func aGameKeepsRawKeys() {
        #expect(CommandTranslation.ctrlKey(typed: "c", keyCode: kVK_ANSI_C, modifiers: [.command],
                                           policy: .lock) == nil)
    }

    @Test func quitTabAndSpaceStayWithMacOS() {
        #expect(CommandTranslation.ctrlKey(typed: "q", keyCode: kVK_ANSI_Q, modifiers: [.command], policy: .free) == nil)
        #expect(CommandTranslation.ctrlKey(typed: "\t", keyCode: kVK_Tab, modifiers: [.command], policy: .free) == nil)
        #expect(CommandTranslation.ctrlKey(typed: " ", keyCode: kVK_Space, modifiers: [.command], policy: .free) == nil)
        #expect(CommandTranslation.ctrlKey(typed: nil, keyCode: kVK_ANSI_C, modifiers: [.command], policy: .free) == nil)
    }

    @Test func aNonLatinLayoutFallsBackToTheKeysUSPosition() {
        // Russian: the C position types с, the Q position types й.
        #expect(CommandTranslation.ctrlKey(typed: "с", keyCode: kVK_ANSI_C, modifiers: [.command], policy: .free) == 0x43)
        #expect(CommandTranslation.ctrlKey(typed: "й", keyCode: kVK_ANSI_Q, modifiers: [.command], policy: .free) == nil)
    }
}

@MainActor
struct CommandChordTests {

    private let down = Int8(StreamProtocol.KEY_ACTION_DOWN)
    private let up = Int8(StreamProtocol.KEY_ACTION_UP)
    private let ctrl = Int8(StreamProtocol.MODIFIER_CTRL)
    private let shift = Int8(StreamProtocol.MODIFIER_SHIFT)

    private func code(_ vk: Int16) -> Int16 { VKScanCode(vk: vk).wireCode }

    private func desktop(ready: Bool = true) -> (InputForwarder, KeyRecordingBackend) {
        let forwarder = InputForwarder()
        let backend = KeyRecordingBackend()
        forwarder.setBackend(backend)
        forwarder.pointerPolicy = .free
        forwarder.isReady = ready
        forwarder.modifiersNeedResync = false
        return (forwarder, backend)
    }

    @Test func commandCSendsExactlyCtrlDownCDownCUpCtrlUp() throws {
        let (forwarder, backend) = desktop()
        let claimed = forwarder.streamView(StreamInputView(), handleKeyEquivalent:
            try keyEvent(kVK_ANSI_C, "c", mods: [.command]))
        #expect(claimed)
        #expect(backend.keys == [
            KeySend(code: code(0xA2), action: down, modifiers: ctrl),
            KeySend(code: code(0x43), action: down, modifiers: ctrl),
            KeySend(code: code(0x43), action: up, modifiers: ctrl),
            KeySend(code: code(0xA2), action: up, modifiers: 0)
        ])
        #expect(forwarder.heldKeys.isEmpty)
        #expect(forwarder.heldModifierVKs.isEmpty)
    }

    @Test func shiftRidesAlongInTheModifierByte() throws {
        let (forwarder, backend) = desktop()
        _ = forwarder.streamView(StreamInputView(), handleKeyEquivalent:
            try keyEvent(kVK_ANSI_Z, "Z", mods: [.command, .shift]))
        #expect(backend.keys.map(\.modifiers) == [ctrl | shift, ctrl | shift, ctrl | shift, shift])
        #expect(backend.keys[1].code == code(0x5A))
    }

    @Test func pasteAndCloseAreClaimedSoTheMenusNeverFire() throws {
        let (forwarder, backend) = desktop()
        let view = StreamInputView()
        #expect(forwarder.streamView(view, handleKeyEquivalent: try keyEvent(kVK_ANSI_V, "v", mods: [.command])))
        #expect(forwarder.streamView(view, handleKeyEquivalent: try keyEvent(kVK_ANSI_W, "w", mods: [.command])))
        #expect(backend.keys.count == 8)
    }

    @Test func quitTabAndOtherCommandChordsStayWithTheMac() throws {
        let (forwarder, backend) = desktop()
        let view = StreamInputView()
        #expect(!forwarder.streamView(view, handleKeyEquivalent: try keyEvent(kVK_ANSI_Q, "q", mods: [.command])))
        #expect(!forwarder.streamView(view, handleKeyEquivalent: try keyEvent(kVK_Tab, "\t", mods: [.command])))
        #expect(!forwarder.streamView(view, handleKeyEquivalent: try keyEvent(kVK_ANSI_C, "c", mods: [.command, .option])))
        #expect(backend.keys.isEmpty)
    }

    @Test func aGameDoesNotTranslate() throws {
        let (forwarder, backend) = desktop()
        forwarder.pointerPolicy = .lock
        #expect(!forwarder.streamView(StreamInputView(), handleKeyEquivalent:
            try keyEvent(kVK_ANSI_V, "v", mods: [.command])))
        #expect(backend.keys.isEmpty)
    }

    @Test func aChordBeforeTheStreamIsLiveBelongsToTheMac() throws {
        let (forwarder, backend) = desktop(ready: false)
        #expect(!forwarder.streamView(StreamInputView(), handleKeyEquivalent:
            try keyEvent(kVK_ANSI_W, "w", mods: [.command])))
        #expect(backend.keys.isEmpty)
    }

    @Test func repeatsSendTheChordAgain() throws {
        let (forwarder, backend) = desktop()
        let view = StreamInputView()
        forwarder.streamView(view, handleKeyDown: try keyEvent(kVK_ANSI_Z, "z", mods: [.command]))
        forwarder.streamView(view, handleKeyDown: try keyEvent(kVK_ANSI_Z, "z", mods: [.command], isRepeat: true))
        #expect(backend.keys.count == 8)
        #expect(backend.keys.filter { $0.code == code(0x5A) && $0.action == down }.count == 2)
    }

    @Test func keyDownBackstopSendsTheSameChordAndKeyUpAddsNothing() throws {
        let (forwarder, backend) = desktop()
        let view = StreamInputView()
        forwarder.streamView(view, handleKeyDown: try keyEvent(kVK_ANSI_C, "c", mods: [.command]))
        #expect(backend.keys.map(\.code) == [code(0xA2), code(0x43), code(0x43), code(0xA2)])
        forwarder.streamView(view, handleKeyUp: try keyEvent(kVK_ANSI_C, "c", mods: [.command], type: .keyUp))
        #expect(backend.keys.count == 4)
    }
}
