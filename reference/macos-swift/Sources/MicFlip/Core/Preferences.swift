import Foundation
import ServiceManagement
import Combine

/// Persistent user settings, backed by UserDefaults. Published so SwiftUI views
/// update live and AppDelegate can react to changes.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.soundEnabled) }
    }

    @Published var visualEnabled: Bool {
        didSet { defaults.set(visualEnabled, forKey: Keys.visualEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    @Published var hotkey: Hotkey {
        didSet {
            if let data = try? JSONEncoder().encode(hotkey) {
                defaults.set(data, forKey: Keys.hotkey)
            }
        }
    }

    private init() {
        // Default the toggles to ON so notifications work out of the box.
        soundEnabled = defaults.object(forKey: Keys.soundEnabled) as? Bool ?? true
        visualEnabled = defaults.object(forKey: Keys.visualEnabled) as? Bool ?? true

        if let data = defaults.data(forKey: Keys.hotkey),
           let hk = try? JSONDecoder().decode(Hotkey.self, from: data) {
            hotkey = hk
        } else {
            hotkey = .default
        }

        // Reflect the real login-item state rather than a stored guess.
        launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("MicFlip: failed to update login item: \(error.localizedDescription)")
        }
    }

    private enum Keys {
        static let soundEnabled = "soundEnabled"
        static let visualEnabled = "visualEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let hotkey = "hotkey"
    }
}
