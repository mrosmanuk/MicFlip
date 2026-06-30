import AppKit

/// Renders the menu bar badge: a bold white "LIVE" on a vibrant red pill when
/// the mic is on/live, and a grayed-out pill when the mic is muted.
enum MicIcon {
    static func image(muted: Bool) -> NSImage {
        let text = "LIVE"
        let backgroundColor: NSColor = muted
            ? NSColor.systemGray.withAlphaComponent(0.40)
            : NSColor.systemRed
        let textColor: NSColor = muted
            ? NSColor.white.withAlphaComponent(0.55)
            : NSColor.white

        let font = NSFont.systemFont(ofSize: 10, weight: .heavy)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
            .kern: 0.3,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)

        let horizontalPadding: CGFloat = 5
        let height: CGFloat = 15
        let width = ceil(textSize.width) + horizontalPadding * 2

        // Flipped so text lays out from the top-left as expected.
        let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5),
                                    xRadius: 3, yRadius: 3)
            backgroundColor.setFill()
            pill.fill()

            let textOrigin = NSPoint(
                x: (rect.width - textSize.width) / 2,
                y: (rect.height - textSize.height) / 2
            )
            (text as NSString).draw(at: textOrigin, withAttributes: attributes)
            return true
        }
        image.isTemplate = false // keep our colors, don't let the menu bar tint it
        return image
    }
}
