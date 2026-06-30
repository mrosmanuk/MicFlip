import SwiftUI
import CoreAudio
import AppKit

/// The main preferences window: notifications, the global shortcut, input
/// device selection, and per-device volume/gain.
struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var controller: MicController

    @State private var devices: [AudioDevice] = []
    @State private var selectedDeviceID: AudioDeviceID = 0
    @State private var volume: Double = 0
    @State private var volumeSupported = false
    @State private var hotkeyNeedsPermission = false

    let hotkeyHasPermission: () -> Bool
    let requestHotkeyPermission: () -> Void
    let openMicCheck: () -> Void

    var body: some View {
        Form {
            Section("Notifications") {
                Toggle("Sound when toggling mic", isOn: $prefs.soundEnabled)
                Toggle("Visual notification (on-screen HUD)", isOn: $prefs.visualEnabled)
                Text("The menu bar icon always shows mic state — these are the extra alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Global Shortcut") {
                HStack {
                    Text("Toggle mute")
                    Spacer()
                    HotkeyRecorderView(hotkey: $prefs.hotkey)
                }
                Text("Hold up to 3 keys at once. Default is ⌘⇧M.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if hotkeyNeedsPermission {
                    HStack(spacing: 8) {
                        Label("Input Monitoring permission is required for the shortcut to work.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Button("Grant…") { requestHotkeyPermission() }
                            .controlSize(.small)
                    }
                }
            }

            Section("Input Device") {
                Picker("Active microphone", selection: $selectedDeviceID) {
                    ForEach(devices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .onChange(of: selectedDeviceID) { _, newValue in
                    guard newValue != 0, newValue != controller.defaultInputDeviceID else { return }
                    controller.selectInputDevice(newValue)
                    refreshVolume()
                }

                if volumeSupported {
                    HStack {
                        Image(systemName: "speaker.fill")
                        Slider(value: $volume, in: 0...1) { editing in
                            if !editing { controller.setVolume(Float(volume), for: selectedDeviceID) }
                        }
                        .onChange(of: volume) { _, newValue in
                            controller.setVolume(Float(newValue), for: selectedDeviceID)
                        }
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    Text("Input gain / volume for the selected device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("This device does not expose an adjustable input volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch MicFlip at login", isOn: $prefs.launchAtLogin)
                Button("Open Mic Check…") { openMicCheck() }
            }

            Section("Support") {
                Button {
                    NSWorkspace.shared.open(AppInfo.donationURL)
                } label: {
                    Label("Buy me a beer 🍺", systemImage: "mug.fill")
                }
                Text("MicFlip is free software. If it saves you from one awkward hot-mic moment, consider chipping in — totally optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("\(AppInfo.name) \(AppInfo.version)")
                    Spacer()
                    Text("\(AppInfo.licenseName) · \(AppInfo.copyright)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear { reload() }
    }

    private func reload() {
        devices = controller.inputDevices()
        selectedDeviceID = controller.defaultInputDeviceID
        hotkeyNeedsPermission = !hotkeyHasPermission()
        refreshVolume()
    }

    private func refreshVolume() {
        volumeSupported = controller.supportsVolume(selectedDeviceID)
        volume = Double(controller.volume(for: selectedDeviceID) ?? 0)
    }
}
