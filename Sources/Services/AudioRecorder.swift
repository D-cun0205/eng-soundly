import AVFoundation
import Foundation

/// Records microphone input and produces 16 kHz mono Float32 samples.
@MainActor
final class AudioRecorder: ObservableObject {
    static let sampleRate: Double = 16_000

    @Published var isRecording = false
    @Published var level: Float = 0     // rough RMS for the level meter

    private let engine = AVAudioEngine()
    private var samples: [Float] = []

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        samples.removeAll()

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
                self?.samples.append(contentsOf: chunk)
                self?.level = rms
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
