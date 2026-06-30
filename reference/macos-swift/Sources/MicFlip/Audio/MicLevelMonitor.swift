import AVFoundation
import Combine

/// Taps the default input device with AVAudioEngine and publishes a normalized
/// 0...1 level for the Mic Check meter. Handles the microphone permission prompt.
@MainActor
final class MicLevelMonitor: ObservableObject {
    /// Normalized input level, 0 (silence) to 1 (loud).
    @Published var level: Float = 0
    /// Whether the engine is currently capturing.
    @Published var isRunning = false
    /// Set when permission is denied so the UI can guide the user.
    @Published var permissionDenied = false

    private let engine = AVAudioEngine()

    func start() {
        guard !isRunning else { return }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            beginTap()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                Task { @MainActor in
                    if granted { self?.beginTap() } else { self?.permissionDenied = true }
                }
            }
        default:
            permissionDenied = true
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        level = 0
    }

    private func beginTap() {
        permissionDenied = false
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0 else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            let level = Self.normalizedLevel(buffer)
            Task { @MainActor in self?.level = level }
        }

        do {
            try engine.start()
            isRunning = true
        } catch {
            NSLog("MicFlip: audio engine failed to start: \(error.localizedDescription)")
        }
    }

    /// Compute RMS, convert to dBFS, and map roughly -60…0 dB onto 0…1.
    private static func normalizedLevel(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }

        var sum: Float = 0
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 1e-7))
        let normalized = (db + 60) / 60
        return min(1, max(0, normalized))
    }
}
