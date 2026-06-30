import AppKit
import CoreAudio

/// Owns the menu bar item: the vibrant icon plus the dropdown menu with toggle,
/// mic check, device switching, and settings.
@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller: MicController

    var openSettings: (() -> Void)?
    var openMicCheck: (() -> Void)?

    private let toggleItem = NSMenuItem(title: "Mute Microphone", action: #selector(toggleMute), keyEquivalent: "")
    private let deviceMenuItem = NSMenuItem(title: "Input Device", action: nil, keyEquivalent: "")

    init(controller: MicController) {
        self.controller = controller
        super.init()
        buildMenu()
        updateIcon(muted: controller.isMuted)
    }

    func updateIcon(muted: Bool) {
        statusItem.button?.image = MicIcon.image(muted: muted)
        statusItem.button?.toolTip = muted ? "Microphone muted" : "Microphone on"
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        toggleItem.target = self
        menu.addItem(toggleItem)

        let micCheck = NSMenuItem(title: "Mic Check…", action: #selector(showMicCheck), keyEquivalent: "")
        micCheck.target = self
        menu.addItem(micCheck)

        menu.addItem(.separator())

        deviceMenuItem.submenu = NSMenu()
        menu.addItem(deviceMenuItem)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let beer = NSMenuItem(title: "Buy Me a Beer 🍺", action: #selector(donate), keyEquivalent: "")
        beer.target = self
        menu.addItem(beer)

        let about = NSMenuItem(title: "About MicFlip", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MicFlip", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        controller.syncFromSystem(notify: false)
        toggleItem.title = controller.isMuted ? "Unmute Microphone" : "Mute Microphone"
        rebuildDeviceMenu()
    }

    private func rebuildDeviceMenu() {
        let submenu = deviceMenuItem.submenu ?? NSMenu()
        submenu.removeAllItems()
        let current = controller.defaultInputDeviceID
        for device in controller.inputDevices() {
            let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = device.id
            item.state = (device.id == current) ? .on : .off
            submenu.addItem(item)
        }
        if submenu.items.isEmpty {
            submenu.addItem(NSMenuItem(title: "No input devices", action: nil, keyEquivalent: ""))
        }
    }

    // MARK: - Actions

    @objc private func toggleMute() { controller.toggle() }
    @objc private func showMicCheck() { openMicCheck?() }
    @objc private func showSettings() { openSettings?() }

    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? AudioDeviceID else { return }
        controller.selectInputDevice(id)
    }

    @objc private func donate() {
        NSWorkspace.shared.open(AppInfo.donationURL)
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)

        let credits = NSMutableAttributedString(
            string: "\(AppInfo.tagline)\n\nFree software under the \(AppInfo.licenseName).\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        let link = NSAttributedString(
            string: "Buy me a beer 🍺",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .link: AppInfo.donationURL,
            ]
        )
        credits.append(link)

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: AppInfo.name,
            .applicationVersion: AppInfo.version,
            .credits: credits,
            .init(rawValue: "Copyright"): AppInfo.copyright,
        ])
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
