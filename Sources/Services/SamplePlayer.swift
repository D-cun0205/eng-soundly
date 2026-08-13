import AVFoundation
import Foundation

/// Plays back raw 16 kHz mono Float32 samples (the user's own recording).
@MainActor
final class SamplePlayer: ObservableObject {
    @Published var isPlaying = false

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: AudioRecorder.sampleRate,
                                       channels: 1, interleaved: false)!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(_ samples: [Float]) {
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count))
        else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)

        do {
            if !engine.isRunning { try engine.start() }
        } catch { return }

        isPlaying = true
        player.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor [weak self] in self?.stop() }
        }
        player.play()
    }

    func stop() {
        player.stop()
        // Leaving the engine running spams CoreAudio errors while idle.
        if engine.isRunning { engine.stop() }
        isPlaying = false
    }
}
