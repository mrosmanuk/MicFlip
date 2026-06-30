import AppKit
import SwiftUI

/// A floating, non-activating HUD (like the macOS volume overlay) that briefly
/// appears center-bottom of the main screen when the mic is toggled.
@MainActor
final class HUDOverlay {
    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    func show(muted: Bool) {
        let panel = panelInstance()
        panel.contentView = NSHostingView(rootView: HUDContentView(muted: muted))
        position(panel)

        hideWorkItem?.cancel()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let work = DispatchWorkItem { [weak self] in self?.fadeOut() }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func fadeOut() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    private func panelInstance() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + frame.height * 0.14
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct HUDContentView: View {
    let muted: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(muted ? Color.red : Color.green)
            Text(muted ? "Microphone Off" : "Microphone On")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .frame(width: 200, height: 200)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }
}
