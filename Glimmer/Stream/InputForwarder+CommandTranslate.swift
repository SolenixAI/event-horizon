//
//  InputForwarder+CommandTranslate.swift
//
//  Mac shortcuts on the PC's Desktop. There ⌘ is the Mac's, so ⌘C reaches the
//  PC as Ctrl+C: ⌘ plus C, V, X, Z, A, S, F or T (⇧ allowed) becomes the
//  same chord on Ctrl. ⌘W is Citadel's: it goes Home (StreamInputView). Only under `.free`; a game keeps raw keys. ⌘Q, ⌘Tab,
//  ⌘Space and every other ⌘ chord are not in the table and stay with macOS.
//

import AppKit

/// The translation table, pure so it is testable without a window or a session.
enum CommandTranslation {
    /// Mac letter to the PC's virtual-key code for it.
    static let letters: [String: Int16] = [
        "c": 0x43, "v": 0x56, "x": 0x58, "z": 0x5A, "a": 0x41,
        "s": 0x53, "f": 0x46, "t": 0x54
    ]

    static let leftControl: Int16 = 0xA2 // VK_LCONTROL

    /// The PC key a ⌘ chord becomes (Ctrl + this key), or nil to leave the chord
    /// with the Mac. ⌘ alone or with ⇧ translates; ⌃ or ⌥ never does. `typed` is
    /// the layout's character; a non-Latin layout falls back to the key's US position.
    static func ctrlKey(
        typed: String?, keyCode: Int, modifiers: NSEvent.ModifierFlags, policy: PointerPolicy
    ) -> Int16? {
        guard policy == .free else { return nil }
        let mods = modifiers.intersection([.command, .shift, .control, .option])
        guard mods.contains(.command), mods.isDisjoint(with: [.control, .option]) else { return nil }
        let letter = (typed ?? "").lowercased()
        if let vk = letters[letter] { return vk }
        guard !letter.allSatisfy(\.isASCII),
              let positional = vkScanCode(forCarbonKeyCode: keyCode)?.vk,
              letters.values.contains(positional) else { return nil }
        return positional
    }
}

extension InputForwarder {

    /// Send a translated ⌘ chord. True when the event is claimed: it must reach
    /// neither the main menu (Edit › Paste, Close Window) nor the PC as a raw key.
    /// A chord pressed before the stream is live is left to the Mac.
    func sendTranslatedCommand(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard isReady, let vk = CommandTranslation.ctrlKey(
            typed: event.charactersIgnoringModifiers, keyCode: Int(event.keyCode),
            modifiers: mods, policy: pointerPolicy) else { return false }
        if modifiersNeedResync { syncModifiers(to: mods) }
        sendCtrlChord(vk, mods: mods)
        return true
    }

    /// LCtrl down, the key down and up, LCtrl up, in one call so no other input
    /// lands inside the chord and the PC never sees a lone Ctrl. Shift, if
    /// held, is already down on the PC through its own modifier events, and a
    /// repeat sends the whole chord again.
    func sendCtrlChord(_ vk: Int16, mods: NSEvent.ModifierFlags) {
        let withCtrl = Int8(bitPattern: modifierByte(from: mods.subtracting(.command).union(.control)))
        let withoutCtrl = Int8(bitPattern: modifierByte(from: mods.subtracting(.command)))
        sendModifier(CommandTranslation.leftControl, down: true, modByte: withCtrl)
        let code = VKScanCode(vk: vk).wireCode
        record("LiSendKeyboardEvent2(down)", backend?.sendKeyboard(
            keyCode: code, action: Int8(StreamProtocol.KEY_ACTION_DOWN), modifiers: withCtrl, flags: 0) ?? -2)
        record("LiSendKeyboardEvent2(up)", backend?.sendKeyboard(
            keyCode: code, action: Int8(StreamProtocol.KEY_ACTION_UP), modifiers: withCtrl, flags: 0) ?? -2)
        sendModifier(CommandTranslation.leftControl, down: false, modByte: withoutCtrl)
    }
}
