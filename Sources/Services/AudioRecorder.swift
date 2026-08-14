import AVFoundation
import Foundation

/// Records microphone input and produces 16 kHz mono Float32 samples.
@MainActor
final class AudioRecorder: ObservableObject {
    static let sampleRate: Double = 16_000

    @Published var isRecording = false
    @Published var level: Float = 0     // rough RMS for the level meter

    /// Called on the main actor when speech was heard and then trailed off
    /// (or the model's 5 s window is nearly full). The owner should stop()
    /// and run diagnosis, same as a manual stop.
    var onAutoStop: (() -> Void)?

    private let engine = AVAudioEngine()
    private var samples: [Float] = []

    // Voice-activity tracking for auto-stop.
    private var heardSpeech = false
    private var silenceSampleRun = 0
    private static let speechRMS: Float = 0.02
    private static let silenceRMS: Float = 0.01
    private static let trailingSilenceSamples = 24_000   // 1.5 s

    /// Hard cap per recording. Word practice keeps this within the model's
    /// 5 s window; free-form mode allows sentences (segmented at recognition).
    var maxSeconds: Double = 15

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        samples.removeAll()
        heardSpeech = false
        silenceSampleRun = 0

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: Self.sampleRate,
                                            channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: inFormat, to: outFormat) else {
            throw NSError(domain: "AudioRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "오디오 포맷 초기화 실패"])
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            let ratio = outFormat.sampleRate / inFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
            guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

            var error: NSError?
            var served = false
            converter.convert(to: out, error: &error) { _, outStatus in
                if served { outStatus.pointee = .noDataNow; return nil }
                served = true
                outStatus.pointee = .haveData
                return buffer
            }
            guard error == nil, out.frameLength > 0, let ch = out.floatChannelData else { return }

            let chunk = Array(UnsafeBufferPointer(start: ch[0], count: Int(out.frameLength)))
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                self.samples.append(contentsOf: chunk)
                self.level = rms

                // Voice-activity: fire onAutoStop once speech has been heard
                // and then trails off, or when the model window is nearly full.
                if rms > Self.speechRMS {
                    self.heardSpeech = true
                    self.silenceSampleRun = 0
                } else if rms < Self.silenceRMS {
                    self.silenceSampleRun += chunk.count
                }
                let trailedOff = self.heardSpeech && self.silenceSampleRun >= Self.trailingSilenceSamples
                if trailedOff || self.samples.count >= Int(self.maxSeconds * Self.sampleRate) {
                    self.onAutoStop?()
                }
            }
        }

        engine.prepare()
        try engine.start()
        isRecording = true
    }

    /// Stops recording and returns the captured 16 kHz samples.
    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return trimSilence(samples)
    }

    /// Trims leading/trailing silence using a simple energy threshold.
    private func trimSilence(_ input: [Float], threshold: Float = 0.008) -> [Float] {
        let window = 320  // 20 ms
        guard input.count > window * 4 else { return input }

        func rms(_ range: Range<Int>) -> Float {
            let slice = input[range]
            return sqrt(slice.reduce(0) { $0 + $1 * $1 } / Float(slice.count))
        }

        var start = 0
        while start + window < input.count, rms(start..<start + window) < threshold { start += window }
        var end = input.count
        while end - window > start, rms(end - window..<end) < threshold { end -= window }

        // Keep 100 ms padding on both sides.
        let pad = 1_600
        start = max(0, start - pad)
        end = min(input.count, end + pad)
        return Array(input[start..<end])
    }
}
