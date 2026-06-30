import AppKit

// MicFlip is a menu-bar-only utility, so we drive NSApplication manually
// rather than relying on a storyboard or @main App scene. Top-level code runs
// on the main thread, so it's safe to assume main-actor isolation here.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory) // no Dock icon, menu bar only
    app.run()
}
