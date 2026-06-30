import AppKit

/// Plays distinct system sounds for mute vs. unmute. Uses built-in macOS
/// sounds so nothing has to be bundled.
enum SoundPlayer {
    private static let muteSound = NSSound(named: "Funk")
    private static let unmuteSound = NSSound(named: "Tink")

    static func play(muted: Bool) {
        let sound = muted ? muteSound : unmuteSound
        sound?.stop()      // restart cleanly if rapidly toggled
        sound?.play()
    }
}
