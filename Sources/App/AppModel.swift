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
    let intent = SpeechIntentService()
    let candidates = WordCandidateService()
    let progress = ProgressStore()
    private(set) var recognizer: PhonemeRecognizer

    /// The samples behind the most recent diagnosis, for "내 발음 듣기".
    private(set) var lastRecording: [Float] = []

    /// One free-form attempt: what was heard acoustically plus what the
    /// user probably meant. The user edits the text, then asks for 교정.
    struct FreeAttempt {
        let samples: [Float]
        let recognized: [RecognizedPhoneme]
        var intentText: String
        var suggestions: [String]     // candidate words / alternative hypotheses
    }

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

        // CMUdict parse (~135k lines) off the main thread, then the
        // candidate lexicon which joins against it.
        Task.detached(priority: .userInitiated) { [dictionary, candidates] in
            dictionary.load()
            candidates.load(dictionary: dictionary)
            await MainActor.run { self.dictionaryReady = dictionary.isLoaded }
        }
    }

    /// Free-form flow, step 1: hear the audio both ways — phonemes (what it
    /// sounded like) and ASR (what was probably meant) — plus candidates.
    func captureFreeAttempt(samples: [Float]) async throws -> FreeAttempt {
        lastRecording = samples

        async let phonemes = recognizer.recognize(samples: samples, targetHint: [])
        async let asr = try? intent.transcribe(samples: samples)

        let recognized = try await phonemes
        let intentResult = await asr

        // Candidate pool: ASR's alternative hypotheses + words that sound
        // like what was actually said. Deduplicated, intent text excluded.
        var pool: [String] = intentResult?.alternatives ?? []
        if recognized.count <= 12 {   // single word / short phrase territory
            let tokens = recognized.map(\.token)
            pool += await Task.detached(priority: .userInitiated) { [candidates] in
                candidates.candidates(for: tokens)
            }.value
        }
        var text = intentResult?.text ?? ""
        var seen = Set([text])
        var suggestions = pool.filter { seen.insert($0).inserted }

        // The context box must always open with our best guess filled in —
        // the chips are for correcting it, not for assembling it. If ASR
        // gave nothing, promote the top sound-alike candidate to the box.
        if text.isEmpty, !suggestions.isEmpty {
            text = suggestions.removeFirst()
        }

        return FreeAttempt(samples: samples, recognized: recognized,
                           intentText: text, suggestions: Array(suggestions.prefix(6)))
    }

    /// Free-form flow, step 2: diagnose the (possibly corrected) text
    /// against the attempt's already-recognized phonemes.
    func diagnoseFree(text: String, attempt: FreeAttempt) throws -> DiagnosisReport {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.init(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else {
            throw NSError(domain: "AppModel", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "교정할 텍스트가 없습니다."])
        }

        let sentence: [WordTarget] = try words.map { word in
            let prons = dictionary.pronunciations(for: word)
            guard !prons.isEmpty else {
                throw NSError(domain: "AppModel", code: 10,
                              userInfo: [NSLocalizedDescriptionKey: "사전에 없는 단어입니다: \(word)"])
            }
            return WordTarget(word: word, variants: prons)
        }

        let report = DiagnosisEngine.diagnose(sentence: sentence, displayText: text,
                                              recognized: attempt.recognized.map(\.token),
                                              confidences: attempt.recognized.map(\.confidence),
                                              usedMock: !recognizer.isRealModel)
        if !report.usedMockRecognizer { progress.record(report) }
        return report
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
        let report = DiagnosisEngine.diagnose(word: word, variants: variants,
                                              recognized: recognized.map(\.token),
                                              confidences: recognized.map(\.confidence),
                                              usedMock: !recognizer.isRealModel)
        if !report.usedMockRecognizer { progress.record(report) }
        return report
    }
}
