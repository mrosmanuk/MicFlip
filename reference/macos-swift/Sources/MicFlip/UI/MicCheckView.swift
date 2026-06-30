import SwiftUI

/// Live microphone level meter so the user can confirm their mic is working
/// (and hear/see whether it's currently muted).
struct MicCheckView: View {
    @ObservedObject var controller: MicController
    @StateObject private var monitor = MicLevelMonitor()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: controller.isMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(controller.isMuted ? .red : .green)
                Text(controller.currentDeviceName)
                    .font(.headline)
                Spacer()
            }

            if monitor.permissionDenied {
                Label("Microphone access denied. Enable it in System Settings → Privacy & Security → Microphone.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                LevelMeter(level: monitor.level)
                    .frame(height: 22)
                Text(controller.isMuted
                     ? "Muted — speak and the meter should stay flat."
                     : "Speak normally — the meter should react.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button(controller.isMuted ? "Unmute" : "Mute") {
                    controller.toggle()
                }
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }
}

/// A segmented horizontal level meter (green → yellow → red).
private struct LevelMeter: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.15))
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [.green, .yellow, .red],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(0, geo.size.width * CGFloat(level)))
                    .animation(.linear(duration: 0.05), value: level)
            }
        }
    }
}
