import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let prefs = Preferences.shared
    private let controller = MicController()
    private let hotkeyManager = HotkeyManager()
    private let hud = HUDOverlay()

    private var statusBar: StatusBarController!
    private var settingsWindow: NSWindow?
    private var micCheckWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(controller: controller)
        statusBar.openSettings = { [weak self] in self?.showSettings() }
        statusBar.openMicCheck = { [weak self] in self?.showMicCheck() }

        // Notify icon / HUD / sound whenever mute state changes.
        controller.onStateChanged = { [weak self] muted, userInitiated in
            guard let self else { return }
            self.statusBar.updateIcon(muted: muted)
            guard userInitiated else { return }
            if self.prefs.visualEnabled { self.hud.show(muted: muted) }
            if self.prefs.soundEnabled { SoundPlayer.play(muted: muted) }
        }

        // Global shortcut.
        hotkeyManager.hotkey = prefs.hotkey
        hotkeyManager.onTrigger = { [weak self] in self?.controller.toggle() }
        prefs.$hotkey
            .sink { [weak self] in self?.hotkeyManager.hotkey = $0 }
            .store(in: &cancellables)

        startHotkey()
    }

    private func startHotkey() {
        // A listen-only tap can be *created* without permission yet receive no
        // events, so we gate on the actual permission check, not on start().
        if hotkeyManager.hasPermission() {
            hotkeyManager.start()
            NSLog("MicFlip: hotkey active (Input Monitoring granted).")
        } else {
            hotkeyManager.requestPermission()
            promptForInputMonitoring()
            pollForInputMonitoring()
        }
    }

    /// Once the user enables Input Monitoring, (re)create the tap so the
    /// shortcut starts working immediately — no relaunch required.
    private func pollForInputMonitoring() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.hotkeyManager.hasPermission() else { return }
            self.hotkeyManager.stop()
            self.hotkeyManager.start()
            self.permissionPollTimer?.invalidate()
            self.permissionPollTimer = nil
            NSLog("MicFlip: Input Monitoring granted — hotkey now active.")
        }
    }

    private func promptForInputMonitoring() {
        let alert = NSAlert()
        alert.messageText = "Enable the global shortcut"
        alert.informativeText = "MicFlip needs Input Monitoring permission to detect your shortcut while other apps are focused.\n\nOpen System Settings → Privacy & Security → Input Monitoring and enable MicFlip. The shortcut activates as soon as you do — no relaunch needed."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    // MARK: - Windows

    private func showSettings() {
        if settingsWindow == nil {
            let view = SettingsView(
                prefs: prefs,
                controller: controller,
                hotkeyHasPermission: { [weak self] in self?.hotkeyManager.hasPermission() ?? false },
                requestHotkeyPermission: { [weak self] in
                    self?.hotkeyManager.requestPermission()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
                        NSWorkspace.shared.open(url)
                    }
                },
                openMicCheck: { [weak self] in self?.showMicCheck() }
            )
            settingsWindow = makeWindow(title: "MicFlip Settings", size: NSSize(width: 460, height: 580), content: view)
        }
        present(settingsWindow)
    }

    private func showMicCheck() {
        if micCheckWindow == nil {
            micCheckWindow = makeWindow(title: "Mic Check", size: NSSize(width: 360, height: 220),
                                        content: MicCheckView(controller: controller))
        }
        present(micCheckWindow)
    }

    private func makeWindow<Content: View>(title: String, size: NSSize, content: Content) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
