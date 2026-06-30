import Foundation

/// App-wide constants: version, author, license, and the donation link.
enum AppInfo {
    static let name = "MicFlip"
    static let version = "1.0"
    static let tagline = "Flip your mic on or off instantly."
    static let author = "Maksim Rosmanuk"
    static let copyright = "© 2026 \(author)"
    static let licenseName = "MIT License"

    /// "Buy me a beer" donation link.
    static let donationURL = URL(string: "https://paypal.me/rosmanuk")!
}
