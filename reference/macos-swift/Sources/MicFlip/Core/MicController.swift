import AppKit
import Combine
import CoreAudio

/// Source of truth for mute state. Owns the audio manager, exposes the current
/// state to SwiftUI, and notifies observers (the menu bar, HUD, sound) on change.
@MainActor
final class MicController: ObservableObject {
    @Published private(set) var isMuted = false
    @Published private(set) var currentDeviceName = "—"

    private let manager = AudioDeviceManager.shared

    /// Called on every state change. `userInitiated` is true only for an
    /// explicit toggle, so notifications don't fire on external/system syncs.
    var onStateChanged: ((_ isMuted: Bool, _ userInitiated: Bool) -> Void)?

    init() {
        manager.startListening()
        manager.onDefaultInputChanged = { [weak self] in
            self?.manager.observeDefaultInputMute()
            self?.syncFromSystem()
        }
        manager.onMuteChanged = { [weak self] in self?.syncFromSystem() }
        manager.observeDefaultInputMute()
        syncFromSystem(notify: false)
    }

    // MARK: - Actions

    func toggle() { setMuted(!isMuted, userInitiated: true) }

    func setMuted(_ muted: Bool, userInitiated: Bool) {
        let device = manager.defaultInputDevice
        manager.setMuted(muted, device: device)
        isMuted = manager.isMuted(device)
        currentDeviceName = manager.deviceName(device) ?? "—"
        onStateChanged?(isMuted, userInitiated)
    }

    /// Re-read the live state from CoreAudio (e.g. after a device or external
    /// mute change). Never counts as user-initiated.
    func syncFromSystem(notify: Bool = true) {
        let device = manager.defaultInputDevice
        isMuted = manager.isMuted(device)
        currentDeviceName = manager.deviceName(device) ?? "—"
        if notify { onStateChanged?(isMuted, false) }
    }

    // MARK: - Device helpers (used by the menu and settings)

    func inputDevices() -> [AudioDevice] { manager.inputDevices() }
    var defaultInputDeviceID: AudioDeviceID { manager.defaultInputDevice }

    func selectInputDevice(_ id: AudioDeviceID) {
        manager.defaultInputDevice = id
        manager.observeDefaultInputMute()
        syncFromSystem()
    }

    func volume(for id: AudioDeviceID) -> Float? { manager.inputVolume(id) }
    func supportsVolume(_ id: AudioDeviceID) -> Bool { manager.supportsVolume(id) }
    func setVolume(_ value: Float, for id: AudioDeviceID) { manager.setInputVolume(value, device: id) }
}
