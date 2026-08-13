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

    func testVoicingOnlyPairDetection() {
        XCTAssertTrue(PhonemeMapping.isVoicingOnlyPair("s", "z"))
        XCTAssertTrue(PhonemeMapping.isVoicingOnlyPair("t", "d"))
        XCTAssertTrue(PhonemeMapping.isVoicingOnlyPair("f", "v"))
        XCTAssertFalse(PhonemeMapping.isVoicingOnlyPair("s", "ʃ"))   // place differs
        XCTAssertFalse(PhonemeMapping.isVoicingOnlyPair("ɑ", "ʌ"))  // vowels
    }
}
