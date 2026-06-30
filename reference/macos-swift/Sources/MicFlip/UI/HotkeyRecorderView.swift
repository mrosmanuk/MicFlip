import SwiftUI
import AppKit

/// SwiftUI wrapper around an AppKit view that records a key chord. Click to
/// start recording, then press up to three keys (with modifiers) at once; the
/// chord is captured when you release them.
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: Hotkey

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onChange = { hotkey = $0 }
        view.hotkey = hotkey
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.hotkey = hotkey
        nsView.refreshTitle()
    }
}

/// Button-like view that captures a simultaneous key chord while focused.
final class RecorderView: NSView {
    var onChange: ((Hotkey) -> Void)?
    var hotkey: Hotkey = .default

    private var isRecording = false
    private var pressedKeys = Set<UInt16>()
    private var maxChordKeys = Set<UInt16>()
    private var maxChordModifiers: UInt = 0
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 30),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        refreshTitle()
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        if isRecording {
            label.stringValue = pressedKeys.isEmpty ? "Press keys…" : currentChord().displayString
        } else {
            label.stringValue = hotkey.isEmpty ? "Click to record shortcut" : hotkey.displayString
        }
    }

    private func updateAppearance() {
        layer?.backgroundColor = (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                                              : NSColor.controlBackgroundColor).cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        startRecording()
    }

    private func startRecording() {
        isRecording = true
        pressedKeys.removeAll()
        maxChordKeys.removeAll()
        maxChordModifiers = 0
        refreshTitle()
        updateAppearance()
    }

    private func finishRecording() {
        isRecording = false
        if !maxChordKeys.isEmpty {
            hotkey = Hotkey(keyCodes: Array(maxChordKeys), modifiers: maxChordModifiers)
            onChange?(hotkey)
        }
        refreshTitle()
        updateAppearance()
    }

    private func currentChord() -> Hotkey {
        Hotkey(keyCodes: Array(pressedKeys), modifiers: maxChordModifiers)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.isARepeat { return }
        if event.keyCode == 0x35 { // Escape cancels
            isRecording = false
            refreshTitle()
            updateAppearance()
            return
        }
        pressedKeys.insert(event.keyCode)
        // Cap at three simultaneous keys.
        if pressedKeys.count > 3 { pressedKeys = Set(pressedKeys.prefix(3)) }
        let mods = event.modifierFlags.rawValue & relevantModifierMask
        if pressedKeys.count >= maxChordKeys.count {
            maxChordKeys = pressedKeys
            maxChordModifiers = mods
        }
        refreshTitle()
    }

    override func keyUp(with event: NSEvent) {
        guard isRecording else { super.keyUp(with: event); return }
        pressedKeys.remove(event.keyCode)
        if pressedKeys.isEmpty { finishRecording() }
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { super.flagsChanged(with: event); return }
        let mods = event.modifierFlags.rawValue & relevantModifierMask
        // Track modifiers as part of the chord while at least one key is held.
        if !pressedKeys.isEmpty && pressedKeys.count >= maxChordKeys.count {
            maxChordModifiers = mods
        }
        refreshTitle()
    }
}
