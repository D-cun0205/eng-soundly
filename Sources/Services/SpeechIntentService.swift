import AVFoundation
import Foundation
import Speech

/// Guesses what the user *meant to say* (intent text) from a recording,
/// using Apple's speech recognizer. This is deliberately the opposite tool
/// from the phoneme model: ASR's context correction — useless for hearing
/// actual sounds — is exactly what's needed to recover intent.
final class SpeechIntentService {

    struct Intent {
        let text: String
        let alternatives: [String]   // other whole-utterance hypotheses
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    /// Transcribes 16 kHz mono samples. Prefers on-device recognition when
    /// the en-US model is installed; otherwise falls back to Apple's server.
    func transcribe(samples: [Float]) async throws -> Intent {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            throw NSError(domain: "SpeechIntent", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "음성 인식을 사용할 수 없습니다."])
        }

        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                   sampleRate: AudioRecorder.sampleRate,
                                   channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              !samples.isEmpty else {
            throw NSError(domain: "SpeechIntent", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "빈 녹음입니다."])
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        request.append(buffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { cont in
            var resumed = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !resumed else { return }
                if let error {
                    resumed = true
                    cont.resume(throwing: error)
                    return
                }
                guard let result, result.isFinal else { return }
                resumed = true
                let all = result.transcriptions.map(\.formattedString)
                    .map { $0.lowercased() }
                    .filter { !$0.isEmpty }
                guard let bestText = all.first else {
                    cont.resume(throwing: NSError(
                        domain: "SpeechIntent", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "무슨 말인지 알아듣지 못했어요."]))
                    return
                }
                cont.resume(returning: Intent(text: bestText,
                                              alternatives: Array(all.dropFirst().prefix(4))))
            }
        }
    }
}
