import Foundation

/// One dictionary word the user might have meant, with its match cost.
struct WordCandidate: Equatable {
    let word: String
    let cost: Double   // lower = closer to what was heard
}

/// Ranks dictionary words by phonetic closeness to a recognized phoneme
/// sequence, breaking near-ties by word frequency ("hello" beats "hollow"
/// unless the audio clearly says otherwise).
enum CandidateRanker {

    /// A lexicon entry: the word, its frequency rank (0 = most common),
    /// and its pronunciation variants in canonical IPA.
    struct Entry {
        let word: String
        let rank: Int
        let variants: [[String]]
    }

    /// Candidates worse than this normalized alignment cost are noise.
    static let maxCost = 0.45
    /// Weight of the log-frequency penalty relative to phonetic cost.
    static let frequencyWeight = 0.018

    static func nearestWords(to recognized: [String],
                             lexicon: [Entry],
                             limit: Int = 5) -> [WordCandidate] {
        guard !recognized.isEmpty else { return [] }

        var results: [WordCandidate] = []
        for entry in lexicon {
            var best = Double.infinity
            for variant in entry.variants {
                // Cheap length prune before the DP alignment.
                if abs(variant.count - recognized.count) > 2 { continue }
                best = min(best, PhonemeAligner.normalizedCost(target: variant,
                                                               actual: recognized))
            }
            guard best <= maxCost else { continue }
            let score = best + frequencyWeight * log(Double(entry.rank + 2))
            results.append(WordCandidate(word: entry.word, cost: score))
        }

        return Array(results.sorted { $0.cost < $1.cost }.prefix(limit))
    }
}
