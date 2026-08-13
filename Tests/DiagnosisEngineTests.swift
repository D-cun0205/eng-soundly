import XCTest
@testable import EngSoundlyCore

/// Regression tests for the diagnosis pipeline: alignment, Korean-L1 rule
/// matching, and the acoustic-model-aware leniency validated against
/// synthesized native speech (see git history for the experiments).
final class DiagnosisEngineTests: XCTestCase {

    private func diagnose(_ word: String, target: [String], actual: [String]) -> DiagnosisReport {
        DiagnosisEngine.diagnose(word: word, variants: [target], recognized: actual, usedMock: false)
    }

    private func koreanIssueTitles(_ report: DiagnosisReport) -> [String] {
        report.issues.filter(\.isKnownKoreanPattern).map(\.title)
    }

    // MARK: - Korean L1 patterns

    func testRiceRAsL() {
        let report = diagnose("rice", target: ["ɹ", "aɪ", "s"], actual: ["l", "aɪ", "s"])
        XCTAssertTrue(koreanIssueTitles(report).contains { $0.contains("ɹ을 l처럼") })
        XCTAssertLessThan(report.score, 100)
    }

    func testCoffeeFAsP() {
        let report = diagnose("coffee", target: ["k", "ɔ", "f", "i"], actual: ["k", "ʌ", "p", "i"])
        XCTAssertTrue(koreanIssueTitles(report).contains { $0.contains("f를 p") })
    }

    func testThinkThAsS() {
        let report = diagnose("think", target: ["θ", "ɪ", "ŋ", "k"], actual: ["s", "ɪ", "ŋ", "k", "ə"])
        let titles = koreanIssueTitles(report)
        XCTAssertTrue(titles.contains { $0.contains("θ를 s") })
        XCTAssertTrue(titles.contains { $0.contains("파열") || $0.contains("모음 삽입") })
    }

    func testStrikeEpenthesis() {
        let report = diagnose("strike", target: ["s", "t", "ɹ", "aɪ", "k"],
                              actual: ["s", "ə", "t", "ə", "l", "aɪ", "k", "ə"])
        let epenthesisCount = koreanIssueTitles(report).filter { $0.contains("모음 삽입") }.count
        XCTAssertGreaterThanOrEqual(epenthesisCount, 2)
        XCTAssertTrue(koreanIssueTitles(report).contains { $0.contains("ɹ을 l처럼") })
        XCTAssertLessThan(report.score, 70)
    }

    func testBirdErVowelSimplification() {
        let report = diagnose("bird", target: ["b", "ɚ", "d"], actual: ["b", "ə", "d", "ɯ"])
        XCTAssertTrue(koreanIssueTitles(report).contains { $0.contains("ɚ") })
    }

    // MARK: - No false flags

    func testPerfectMatchScoresFull() {
        let report = diagnose("sea", target: ["s", "i"], actual: ["s", "i"])
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testFlapIsAllophoneNotError() {
        let report = diagnose("water", target: ["w", "ɔ", "t", "ɚ"], actual: ["w", "ɔ", "ɾ", "ɚ"])
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testCotCaughtMergerNotError() {
        // GA speakers (and the acoustic model) realize dictionary /ɔ/ as [ɑ].
        let report = diagnose("coffee", target: ["k", "ɔ", "f", "i"], actual: ["k", "ɑ", "f", "i"])
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testWordFinalVoicingNotError() {
        // The model cannot hear word-final voicing reliably (rice → /ɹ aɪ z/).
        let report = diagnose("rice", target: ["ɹ", "aɪ", "s"], actual: ["ɹ", "aɪ", "z"])
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testNonFinalVoicingStillFlagged() {
        let report = diagnose("sink", target: ["s", "ɪ", "ŋ", "k"], actual: ["z", "ɪ", "ŋ", "k"])
        XCTAssertFalse(report.issues.isEmpty)
    }

    // MARK: - Confidence gating

    func testLowConfidenceSubstitutionNotFlagged() {
        // r→l heard, but the model was unsure about the l — don't flag it.
        let report = DiagnosisEngine.diagnose(
            word: "rice", variants: [["ɹ", "aɪ", "s"]],
            recognized: ["l", "aɪ", "s"],
            confidences: [0.3, 0.99, 0.99], usedMock: false)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.score, 100)
    }

    func testHighConfidenceSubstitutionStillFlagged() {
        let report = DiagnosisEngine.diagnose(
            word: "rice", variants: [["ɹ", "aɪ", "s"]],
            recognized: ["l", "aɪ", "s"],
            confidences: [0.9, 0.99, 0.99], usedMock: false)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertLessThan(report.score, 100)
    }

    func testLowConfidenceInsertionNotFlagged() {
        // Faint trailing vowel the model barely believes in → ignore.
        let report = DiagnosisEngine.diagnose(
            word: "think", variants: [["θ", "ɪ", "ŋ", "k"]],
            recognized: ["θ", "ɪ", "ŋ", "k", "ə"],
            confidences: [0.9, 0.9, 0.9, 0.9, 0.2], usedMock: false)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertEqual(report.score, 100)
    }

    func testDeletionNotAffectedByGating() {
        // Deletions consume no recognized token — gating must not skip them.
        let report = DiagnosisEngine.diagnose(
            word: "think", variants: [["θ", "ɪ", "ŋ", "k"]],
            recognized: ["θ", "ɪ", "ŋ"],
            confidences: [0.9, 0.9, 0.9], usedMock: false)
        XCTAssertFalse(report.issues.isEmpty)
    }

    // MARK: - Phoneme mapping

    func testArpabetToIPA() {
        XCTAssertEqual(["R", "AY1", "S"].compactMap { PhonemeMapping.arpabetToIPA($0) },
                       ["ɹ", "aɪ", "s"])
        XCTAssertEqual(["W", "AO1", "T", "ER0"].compactMap { PhonemeMapping.arpabetToIPA($0) },
                       ["w", "ɔ", "t", "ɚ"])
        XCTAssertEqual(["AH0", "B", "AH1", "V"].compactMap { PhonemeMapping.arpabetToIPA($0) },
                       ["ə", "b", "ʌ", "v"])
    }

    func testEspeakNormalization() {
        // Stress marks and <pad> drop; length marks strip; ɜː → ɝ family; r → ɹ.
        let tokens = ["ɹ", "aɪ", "s", "ˈ", "iː", "ɾ", "ɜː", "r", "a", "<pad>"]
        let normalized = tokens.compactMap { PhonemeMapping.normalizeRecognized($0) }
        XCTAssertFalse(normalized.contains("ˈ"))
        XCTAssertFalse(normalized.contains("<pad>"))
        XCTAssertTrue(normalized.contains("ɹ"))
        XCTAssertFalse(normalized.contains("r"))
        XCTAssertFalse(normalized.contains { $0.contains("ː") })
    }

    // MARK: - Sentence mode

    private func sentenceTargets(_ pairs: [(String, [[String]])]) -> [WordTarget] {
        pairs.map { WordTarget(word: $0.0, variants: $0.1) }
    }

    func testSentencePerWordScoresAndAttribution() {
        // "rice light": rice said with r→l, light said perfectly.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("rice", [["ɹ", "aɪ", "s"]]),
                ("light", [["l", "aɪ", "t"]]),
            ]),
            recognized: ["l", "aɪ", "s", "l", "aɪ", "t"], usedMock: false)

        XCTAssertEqual(report.wordScores.count, 2)
        XCTAssertLessThan(report.wordScores[0].score, 100)   // rice has the error
        XCTAssertEqual(report.wordScores[1].score, 100)      // light is clean
        XCTAssertEqual(report.issues.count, 1)
        XCTAssertEqual(report.issues[0].word, "rice")        // attributed correctly
    }

    func testSentencePicksBestVariantPerWord() {
        // "the" has ði/ðə variants; the speaker said ði — no error either way.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("the", [["ð", "ə"], ["ð", "i"]]),
                ("light", [["l", "aɪ", "t"]]),
            ]),
            recognized: ["ð", "i", "l", "aɪ", "t"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testSentenceWordFinalVoicingLenientPerWord() {
        // Voicing leniency applies at EVERY word's final position, not just
        // the utterance end: "rice light" heard as [ɹ aɪ z][l aɪ d].
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("rice", [["ɹ", "aɪ", "s"]]),
                ("light", [["l", "aɪ", "t"]]),
            ]),
            recognized: ["ɹ", "aɪ", "z", "l", "aɪ", "d"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testSentenceFindsLateDictionaryVariant() {
        // "to" is /tə/ in running speech — its THIRD dictionary form. The
        // variant chooser must reach it (a capped cartesian product didn't).
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("want", [["w", "ɑ", "n", "t"]]),
                ("to", [["t", "u"], ["t", "ɪ"], ["t", "ə"]]),
                ("go", [["ɡ", "oʊ"]]),
            ]),
            recognized: ["w", "ɑ", "n", "t", "t", "ə", "ɡ", "oʊ"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testFullVowelVsWedgeNotFlagged() {
        // Native "want" comes back [w ʌ n t] against dictionary /w ɑ n t/.
        let report = diagnose("want", target: ["w", "ɑ", "n", "t"],
                              actual: ["w", "ʌ", "n", "t"])
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testSingleWordReportHasOneWordScore() {
        let report = diagnose("sea", target: ["s", "i"], actual: ["s", "i"])
        XCTAssertEqual(report.wordScores.count, 1)
        XCTAssertNil(report.issues.first?.word)   // no word tags in word mode
    }

    // MARK: - Liaison / connected speech

    func testWannaContractionAchieved() {
        // "want to go" spoken as [w ɑ n ə ɡ oʊ] (wanna): perfect score,
        // no issues, and the contraction is recognized as achieved.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("want", [["w", "ɑ", "n", "t"]]),
                ("to", [["t", "u"], ["t", "ɪ"], ["t", "ə"]]),
                ("go", [["ɡ", "oʊ"]]),
            ]),
            recognized: ["w", "ɑ", "n", "ə", "ɡ", "oʊ"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.liaisonTips.contains { $0.achieved && $0.title.contains("wanna") })
    }

    func testCarefulSpeechGetsSuggestionNotError() {
        // Careful "want to go" [w ɑ n t t u ɡ oʊ]: still 100 — liaison is
        // a tip, never an error.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("want", [["w", "ɑ", "n", "t"]]),
                ("to", [["t", "u"], ["t", "ɪ"], ["t", "ə"]]),
                ("go", [["ɡ", "oʊ"]]),
            ]),
            recognized: ["w", "ɑ", "n", "t", "t", "u", "ɡ", "oʊ"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.liaisonTips.contains { !$0.achieved && $0.title.contains("wanna") })
    }

    func testPalatalizationDidYou() {
        // "did you" as [d ɪ dʒ u] (디쥬): achieved palatalization, no issues.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("did", [["d", "ɪ", "d"]]),
                ("you", [["j", "u"]]),
            ]),
            recognized: ["d", "ɪ", "dʒ", "u"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.liaisonTips.contains(where: \.achieved))
    }

    func testWeakFormAndAccepted() {
        // "you and me" with reduced and → [ə n]: correct running speech.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("you", [["j", "u"]]),
                ("and", [["æ", "n", "d"]]),
                ("me", [["m", "i"]]),
            ]),
            recognized: ["j", "u", "ə", "n", "m", "i"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testElisionBestFriend() {
        // "best friend" without the t between consonants: natural, no issue.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("best", [["b", "ɛ", "s", "t"]]),
                ("friend", [["f", "ɹ", "ɛ", "n", "d"]]),
            ]),
            recognized: ["b", "ɛ", "s", "f", "ɹ", "ɛ", "n", "d"], usedMock: false)
        XCTAssertEqual(report.score, 100)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testRealErrorStillFlaggedInLiaisonContext() {
        // "want to go" as wanna but with r→l in "go"... no r here; use
        // f→p in "coffee": wanna-style reduction plus a genuine error must
        // still flag the error.
        let report = DiagnosisEngine.diagnose(
            sentence: sentenceTargets([
                ("want", [["w", "ɑ", "n", "t"]]),
                ("to", [["t", "u"], ["t", "ə"]]),
                ("drink", [["d", "ɹ", "ɪ", "ŋ", "k"]]),
            ]),
            recognized: ["w", "ɑ", "n", "ə", "d", "l", "ɪ", "ŋ", "k"], usedMock: false)
        XCTAssertFalse(report.issues.isEmpty)
        XCTAssertEqual(report.issues.first?.word, "drink")
        XCTAssertTrue(report.liaisonTips.contains(where: \.achieved))
    }

    func testSingleWordHasNoLiaisonTips() {
        let report = diagnose("you", target: ["j", "u"], actual: ["j", "u"])
        XCTAssertTrue(report.liaisonTips.isEmpty)
        XCTAssertEqual(report.score, 100)
    }

    // MARK: - Progress tracking & drills

    @MainActor
    func testProgressAccumulatesAttemptsAndErrors() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = ProgressStore(fileURL: tmp)

        // rice with r→l: ɹ attempted+errored; aɪ, s attempted clean.
        store.record(diagnose("rice", target: ["ɹ", "aɪ", "s"], actual: ["l", "aɪ", "s"]))
        store.record(diagnose("rice", target: ["ɹ", "aɪ", "s"], actual: ["l", "aɪ", "s"]))
        store.record(diagnose("rice", target: ["ɹ", "aɪ", "s"], actual: ["ɹ", "aɪ", "s"]))

        XCTAssertEqual(store.stats["ɹ"]?.attempts, 3)
        XCTAssertEqual(store.stats["ɹ"]?.errors, 2)
        XCTAssertEqual(store.stats["aɪ"]?.errors, 0)

        let weak = store.weakestPhonemes
        XCTAssertEqual(weak.first?.phoneme, "ɹ")
        // Clean phonemes (0 errors) never appear as "weak".
        XCTAssertFalse(weak.contains { $0.phoneme == "aɪ" })

        // Round-trips through disk.
        let reloaded = ProgressStore(fileURL: tmp)
        XCTAssertEqual(reloaded.stats["ɹ"], store.stats["ɹ"])
    }

    @MainActor
    func testProgressIgnoresLenientMismatches() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("progress-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let store = ProgressStore(fileURL: tmp)

        // Word-final voicing (rice → raɪz) is leniency-skipped → no error.
        store.record(diagnose("rice", target: ["ɹ", "aɪ", "s"], actual: ["ɹ", "aɪ", "z"]))
        XCTAssertEqual(store.stats["s"]?.attempts, 1)
        XCTAssertEqual(store.stats["s"]?.errors, 0)
    }

    func testDrillBuilderFindsCommonWordsWithPhoneme() {
        let lexicon: [CandidateRanker.Entry] = [
            .init(word: "the", rank: 0, variants: [["ð", "ə"]]),          // too short (2)
            .init(word: "think", rank: 10, variants: [["θ", "ɪ", "ŋ", "k"]]),
            .init(word: "birthday", rank: 40, variants: [["b", "ɚ", "θ", "d", "eɪ"]]),
            .init(word: "sink", rank: 5, variants: [["s", "ɪ", "ŋ", "k"]]),  // no θ
        ]
        let words = DrillBuilder.words(containing: "θ", lexicon: lexicon)
        XCTAssertEqual(words, ["think", "birthday"])   // frequency order, θ only
    }

    // MARK: - Audio segmentation

    func testSegmenterShortAudioUntouched() {
        let audio = [Float](repeating: 0.1, count: 1_000)
        let segments = AudioSegmenter.segment(audio, window: 80_000)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].count, 1_000)
    }

    func testSegmenterCutsAtQuietestPointAndPreservesAllSamples() {
        // 12 s of "speech" with a silent gap at 4.0–4.3 s: the first cut
        // (search zone 3.0–5.0 s) must land inside the gap.
        var audio = [Float](repeating: 0.3, count: 192_000)
        for i in 64_000..<68_800 { audio[i] = 0 }
        let segments = AudioSegmenter.segment(audio, window: 80_000)

        XCTAssertGreaterThanOrEqual(segments.count, 2)
        XCTAssertTrue((64_000...68_800).contains(segments[0].count),
                      "first cut at \(segments[0].count), expected inside the silent gap")
        XCTAssertTrue(segments.allSatisfy { $0.count <= 80_000 })
        XCTAssertEqual(segments.reduce(0) { $0 + $1.count }, audio.count)
    }

    // MARK: - Candidate ranking

    private let miniLexicon: [CandidateRanker.Entry] = [
        .init(word: "hello", rank: 100, variants: [["h", "ə", "l", "oʊ"], ["h", "ɛ", "l", "oʊ"]]),
        .init(word: "hollow", rank: 5_000, variants: [["h", "ɑ", "l", "oʊ"]]),
        .init(word: "halo", rank: 12_000, variants: [["h", "eɪ", "l", "oʊ"]]),
        .init(word: "world", rank: 300, variants: [["w", "ɚ", "l", "d"]]),
    ]

    func testCandidateExactMatchWinsAndNearMissFollows() {
        // Clear [h ɛ l oʊ] → hello first; hollow appears as a candidate.
        let result = CandidateRanker.nearestWords(to: ["h", "ɛ", "l", "oʊ"],
                                                  lexicon: miniLexicon)
        XCTAssertEqual(result.first?.word, "hello")
        XCTAssertTrue(result.map(\.word).contains("hollow"))
        XCTAssertFalse(result.map(\.word).contains("world"))
    }

    func testCandidateFrequencyBreaksPhoneticTie() {
        // [h ʌ l oʊ] sits between hello(ə) and hollow(ɑ) — the far more
        // common "hello" should outrank "hollow".
        let result = CandidateRanker.nearestWords(to: ["h", "ʌ", "l", "oʊ"],
                                                  lexicon: miniLexicon)
        let words = result.map(\.word)
        XCTAssertLessThan(words.firstIndex(of: "hello") ?? .max,
                          words.firstIndex(of: "hollow") ?? .max)
    }

    func testCandidateEmptyInputGivesNothing() {
        XCTAssertTrue(CandidateRanker.nearestWords(to: [], lexicon: miniLexicon).isEmpty)
    }

    func testVoicingOnlyPairDetection() {
        XCTAssertTrue(PhonemeMapping.isVoicingOnlyPair("s", "z"))
        XCTAssertTrue(PhonemeMapping.isVoicingOnlyPair("t", "d"))
        XCTAssertTrue(PhonemeMapping.isVoicingOnlyPair("f", "v"))
        XCTAssertFalse(PhonemeMapping.isVoicingOnlyPair("s", "ʃ"))   // place differs
        XCTAssertFalse(PhonemeMapping.isVoicingOnlyPair("ɑ", "ʌ"))  // vowels
    }
}
