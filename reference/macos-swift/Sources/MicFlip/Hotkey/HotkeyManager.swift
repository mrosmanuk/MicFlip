import AppKit
import CoreGraphics

/// Listens for a global keyboard chord via a CGEventTap and fires `onTrigger`
/// when exactly the configured keys + modifiers are held at once. A listen-only
/// tap is used so keystrokes still reach the focused app. Supports up to three
/// simultaneous non-modifier keys, which is why we can't use Carbon hotkeys.
final class HotkeyManager {
    var onTrigger: (() -> Void)?
    var hotkey: Hotkey?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var pressedKeys = Set<UInt16>()
    private var currentModifiers: UInt = 0
    private var hasFired = false

    // MARK: - Permission (Input Monitoring)

    func hasPermission() -> Bool { CGPreflightListenEventAccess() }

    @discardableResult
    func requestPermission() -> Bool { CGRequestListenEventAccess() }

    // MARK: - Lifecycle

    /// Starts the tap. Returns false if the tap could not be created (usually
    /// because Input Monitoring permission has not been granted yet).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        runLoopSource = nil
        pressedKeys.removeAll()
        hasFired = false
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap that takes too long or on user input; re-arm it.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        switch type {
        case .flagsChanged:
            currentModifiers = UInt(truncatingIfNeeded: event.flags.rawValue) & relevantModifierMask
            evaluate()
        case .keyDown:
            // Ignore key-repeat events while a key is held.
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }
            pressedKeys.insert(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            evaluate()
        case .keyUp:
            pressedKeys.remove(UInt16(event.getIntegerValueField(.keyboardEventKeycode)))
            hasFired = false // allow the next full press to trigger again
        default:
            break
        }
    }

    private func evaluate() {
        guard let hotkey, !hotkey.isEmpty, !hasFired else { return }
        let keysMatch = Set(hotkey.keyCodes) == pressedKeys
        let modsMatch = (hotkey.modifiers & relevantModifierMask) == currentModifiers
        if keysMatch && modsMatch {
            hasFired = true
            NSLog("MicFlip: hotkey chord matched — toggling.")
            onTrigger?()
        }
    }
}
