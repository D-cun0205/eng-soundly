import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var categories: [WordCategory] = []
    @Published var dictionaryReady = false
    @Published var isDemoMode = true   // true until the Core ML model is bundled

    let dictionary = PronunciationDictionary()
    let recorder = AudioRecorder()
    let tts = TTSService()
    let player = SamplePlayer()
    private(set) var recognizer: PhonemeRecognizer

    /// The samples behind the most recent diagnosis, for "내 발음 듣기".
    private(set) var lastRecording: [Float] = []

    init() {
        if let real = CoreMLPhonemeRecognizer() {
            recognizer = real
            isDemoMode = false
            Task.detached(priority: .utility) { await real.warmUp() }
        } else {
            recognizer = MockPhonemeRecognizer()
            isDemoMode = true
        }

        categories = WordCatalog.load()

        // CMUdict parse (~135k lines) off the main thread.
        Task.detached(priority: .userInitiated) { [dictionary] in
            dictionary.load()
            await MainActor.run { self.dictionaryReady = dictionary.isLoaded }
        }
    }

    /// Run the full pipeline for one attempt.
    func diagnose(word: String, samples: [Float]) async throws -> DiagnosisReport {
        let variants = dictionary.pronunciations(for: word)
        guard !variants.isEmpty else {
            throw NSError(domain: "AppModel", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "사전에 없는 단어입니다: \(word)"])
        }
        lastRecording = samples
        let recognized = try await recognizer.recognize(samples: samples,
                                                        targetHint: variants[0])
        return DiagnosisEngine.diagnose(word: word, variants: variants,
                                        recognized: recognized.map(\.token),
                                        confidences: recognized.map(\.confidence),
                                        usedMock: !recognizer.isRealModel)
    }
}
