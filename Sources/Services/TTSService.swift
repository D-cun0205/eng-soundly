import AVFoundation
import Foundation

/// Plays native (en-US) reference pronunciation via AVSpeechSynthesizer.
@MainActor
final class TTSService: NSObject, ObservableObject {
    @Published var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, rate: Float = AVSpeechUtteranceDefaultSpeechRate) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        // Prefer an enhanced/premium US voice when installed.
        let usVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        utterance.voice = usVoices.first { $0.quality == .premium }
            ?? usVoices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func speakSlowly(_ text: String) {
        speak(text, rate: AVSpeechUtteranceDefaultSpeechRate * 0.6)
    }
}

extension TTSService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
