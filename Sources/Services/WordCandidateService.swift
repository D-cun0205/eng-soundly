import Foundation

/// Serves "did you mean…" word candidates for a recognized phoneme sequence,
/// backed by the bundled frequency list (word_freq.txt, most-common-first)
/// joined with CMUdict pronunciations.
final class WordCandidateService {
    private var lexicon: [CandidateRanker.Entry] = []
    private(set) var isLoaded = false

    /// Builds the lexicon once; call after PronunciationDictionary is loaded.
    func load(dictionary: PronunciationDictionary) {
        guard let url = Bundle.main.url(forResource: "word_freq", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        var entries: [CandidateRanker.Entry] = []
        entries.reserveCapacity(40_000)
        var rank = 0
        text.enumerateLines { word, _ in
            let variants = dictionary.pronunciations(for: word)
            if !variants.isEmpty {
                entries.append(CandidateRanker.Entry(word: word, rank: rank, variants: variants))
            }
            rank += 1
        }
        lexicon = entries
        isLoaded = true
    }

    /// Top word candidates for what the user's audio actually sounded like.
    func candidates(for recognized: [String], limit: Int = 5) -> [String] {
        CandidateRanker.nearestWords(to: recognized, lexicon: lexicon, limit: limit)
            .map(\.word)
    }

    /// Common words containing a phoneme, for weak-phoneme drills.
    func drillWords(for phoneme: String, limit: Int = 8) -> [String] {
        DrillBuilder.words(containing: phoneme, lexicon: lexicon, limit: limit)
    }
}
