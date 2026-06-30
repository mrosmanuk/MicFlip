import AppKit

/// The set of modifier bits MicFlip cares about. NSEvent.ModifierFlags and
/// CGEventFlags share the same device-independent bit layout for these, so we
/// can compare a recorded NSEvent chord against a live CGEvent tap directly.
let relevantModifierMask: UInt = NSEvent.ModifierFlags([.command, .option, .control, .shift, .function]).rawValue

/// A global shortcut: zero or more modifier keys held together with one to
/// three regular keys, all pressed simultaneously.
struct Hotkey: Codable, Equatable {
    /// Non-modifier key codes that must all be held down.
    var keyCodes: [UInt16]
    /// NSEvent.ModifierFlags raw value, masked to `relevantModifierMask`.
    var modifiers: UInt

    init(keyCodes: [UInt16], modifiers: UInt) {
        self.keyCodes = keyCodes.sorted()
        self.modifiers = modifiers & relevantModifierMask
    }

    var isEmpty: Bool { keyCodes.isEmpty }

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// Human-readable representation, e.g. "⌘⇧M" or "⌃A B".
    var displayString: String {
        var parts = ""
        let flags = modifierFlags
        if flags.contains(.control) { parts += "⌃" }
        if flags.contains(.option) { parts += "⌥" }
        if flags.contains(.shift) { parts += "⇧" }
        if flags.contains(.command) { parts += "⌘" }
        if flags.contains(.function) { parts += "fn" }
        let keys = keyCodes.map { KeyNames.string(for: $0) }.joined(separator: " ")
        return parts + keys
    }

    /// A sensible default so the app is usable on first launch: ⌘⇧M.
    static let `default` = Hotkey(keyCodes: [0x2E], modifiers: NSEvent.ModifierFlags([.command, .shift]).rawValue)
}
