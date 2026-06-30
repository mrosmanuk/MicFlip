import CoreAudio
import AudioToolbox
import Foundation

struct AudioDevice: Identifiable, Hashable {
    let id: AudioDeviceID
    let uid: String
    let name: String
}

/// Thin wrapper over CoreAudio's HAL for the operations MicFlip needs:
/// enumerate input devices, read/switch the default input, mute/unmute, and
/// read/set input volume. Muting the device's hardware input means every app
/// (Zoom, Meet, Teams, …) receives silence — a true OS-level mute.
final class AudioDeviceManager {
    static let shared = AudioDeviceManager()

    /// Fired on the main queue when the device list changes (plug/unplug).
    var onDevicesChanged: (() -> Void)?
    /// Fired on the main queue when the system default input device changes.
    var onDefaultInputChanged: (() -> Void)?
    /// Fired on the main queue when the observed device's mute state changes.
    var onMuteChanged: (() -> Void)?

    /// Previous volume per device UID, so a volume-based mute can be reversed
    /// on devices that don't expose a settable mute property.
    private var volumeBackup: [String: Float] = [:]

    private init() {}

    // MARK: - Property address helper

    private func address(_ selector: AudioObjectPropertySelector,
                         _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                         _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: - Default input device

    var defaultInputDevice: AudioDeviceID {
        get {
            var addr = address(kAudioHardwarePropertyDefaultInputDevice)
            var dev = AudioDeviceID(0)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev)
            return dev
        }
        set {
            var addr = address(kAudioHardwarePropertyDefaultInputDevice)
            var dev = newValue
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &dev)
        }
    }

    // MARK: - Enumeration

    func inputDevices() -> [AudioDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else {
            return []
        }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return ids.compactMap { id in
            guard hasInput(id) else { return nil }
            return AudioDevice(id: id, uid: deviceUID(id) ?? "\(id)", name: deviceName(id) ?? "Unknown device")
        }
    }

    private func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return false }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, raw) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        for buffer in list where buffer.mNumberChannels > 0 { return true }
        return false
    }

    // MARK: - Names

    func deviceName(_ id: AudioDeviceID) -> String? {
        stringProperty(id, kAudioObjectPropertyName)
    }

    func deviceUID(_ id: AudioDeviceID) -> String? {
        stringProperty(id, kAudioDevicePropertyDeviceUID)
    }

    private func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var str: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &str) == noErr,
              let value = str?.takeRetainedValue() else { return nil }
        return value as String
    }

    // MARK: - Mute

    /// True if the device is currently muted. Because our effective mute zeroes
    /// the input volume, a near-zero volume counts as muted; we also honor the
    /// hardware mute flag for devices that only expose that.
    func isMuted(_ id: AudioDeviceID) -> Bool {
        if let volume = inputVolume(id), volume <= 0.0001 { return true }

        var sawMuteProperty = false
        var muted = false
        for element in muteElements {
            var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr {
                sawMuteProperty = true
                if value == 1 { muted = true }
            }
        }
        return sawMuteProperty ? muted : false
    }

    func setMuted(_ muted: Bool, device id: AudioDeviceID) {
        guard id != 0 else { return }
        let uid = deviceUID(id) ?? "\(id)"

        // Zeroing the input gain is the most reliable silencer: many USB mics
        // expose a mute flag that *reports* muted yet still pass audio to apps,
        // so when the device has a settable volume we drive it to zero and
        // restore the previous value on unmute.
        if supportsVolume(id) {
            if muted {
                if let volume = inputVolume(id), volume > 0.0001 { volumeBackup[uid] = volume }
                setInputVolume(0, device: id)
            } else {
                setInputVolume(volumeBackup[uid] ?? 1.0, device: id)
            }
        }

        // Also set the hardware mute flag where present — it gives a proper
        // indication in System Settings and is a real mute on devices that
        // honor it (and is the only lever on devices with no volume control).
        _ = setMuteProperty(muted, device: id)
    }

    private func setMuteProperty(_ muted: Bool, device id: AudioDeviceID) -> Bool {
        var didSet = false
        var value: UInt32 = muted ? 1 : 0
        for element in muteElements {
            var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { continue }
            if AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr {
                didSet = true
            }
        }
        return didSet
    }

    // MARK: - Volume

    func inputVolume(_ id: AudioDeviceID) -> Float? {
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput, element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr {
                return Float(value)
            }
        }
        return nil
    }

    @discardableResult
    func setInputVolume(_ value: Float, device id: AudioDeviceID) -> Bool {
        var didSet = false
        var scalar = Float32(max(0, min(1, value)))
        for element in volumeElements {
            var addr = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeInput, element)
            guard AudioObjectHasProperty(id, &addr) else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(id, &addr, &settable) == noErr, settable.boolValue else { continue }
            if AudioObjectSetPropertyData(id, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr {
                didSet = true
            }
        }
        return didSet
    }

    /// Whether this device exposes any settable input volume control.
    func supportsVolume(_ id: AudioDeviceID) -> Bool {
        inputVolume(id) != nil
    }

    // master element first, then channels 1 & 2 for devices without a master.
    private var muteElements: [AudioObjectPropertyElement] { [kAudioObjectPropertyElementMain, 1, 2] }
    private var volumeElements: [AudioObjectPropertyElement] { [kAudioObjectPropertyElementMain, 1, 2] }

    // MARK: - Change listeners

    func startListening() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var deviceListAddr = address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(system, &deviceListAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.onDevicesChanged?()
        }
        var defaultAddr = address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(system, &defaultAddr, DispatchQueue.main) { [weak self] _, _ in
            self?.onDefaultInputChanged?()
        }
    }

    private var muteListenerBlock: AudioObjectPropertyListenerBlock?
    private var muteListenerDevice: AudioDeviceID?

    /// Watch the current default input device for external mute changes so the
    /// menu bar icon stays in sync when another app or the user toggles it.
    func observeDefaultInputMute() {
        removeMuteObserver()
        let id = defaultInputDevice
        guard id != 0 else { return }
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(id, &addr) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onMuteChanged?() }
        if AudioObjectAddPropertyListenerBlock(id, &addr, DispatchQueue.main, block) == noErr {
            muteListenerBlock = block
            muteListenerDevice = id
        }
    }

    private func removeMuteObserver() {
        guard let block = muteListenerBlock, let id = muteListenerDevice else { return }
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(id, &addr, DispatchQueue.main, block)
        muteListenerBlock = nil
        muteListenerDevice = nil
    }
}
