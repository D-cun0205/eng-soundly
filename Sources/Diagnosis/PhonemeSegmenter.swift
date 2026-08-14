import Foundation

/// Reconstructs the sentence a phoneme stream most likely spells, by
/// segmenting it into dictionary words (dynamic programming over the
/// frequency-ordered lexicon). This is the ASR-free fallback for guessing
/// what the user meant: it knows nothing about grammar, only about how
/// words sound and how common they are.
enum PhonemeSegmenter {

    /// Weight of the log-frequency penalty per word (same spirit as
    /// CandidateRanker: common words win near-ties).
    static let frequencyWeight = 0.018
    /// Fixed cost per word, so the DP prefers fewer, longer words over
    /// shredding the stream into many tiny function words.
    static let perWordPenalty = 0.35
    /// Reject segmentations whose average per-phoneme match cost is worse
    /// than this — better no guess than a hallucinated sentence.
    static let maxAverageCost = 0.5

    /// Returns the best word segmentation of `recognized`, or nil when
    /// nothing in the vocabulary explains the audio well enough.
    static func segment(_ recognized: [String],
                        lexicon: [CandidateRanker.Entry],
                        vocabularyLimit: Int = 3_000,
                        maxPhonemes: Int = 48) -> [String]? {
        let n = recognized.count
        guard n >= 2, n <= maxPhonemes else { return nil }
        let vocab = Array(lexicon.prefix(vocabularyLimit))

        // dp[i] = best cost to segment recognized[0..<i]; back[i] = (word, start)
        var dp = [Double](repeating: .infinity, count: n + 1)
        var back = [(word: String, from: Int)?](repeating: nil, count: n + 1)
        dp[0] = 0

        for i in 0..<n where dp[i] < .infinity {
            let head = recognized[i]
            for entry in vocab {
                let freqPenalty = frequencyWeight * log(Double(entry.rank + 2))
                for variant in entry.variants {
                    let m = variant.count
                    guard m >= 1,
                          // First-phoneme gate: a word whose onset can't
                          // plausibly be `head` never wins — skip the DP.
                          PhonemeMapping.substitutionCost(variant[0], head) < 0.9
                    else { continue }

                    for len in max(1, m - 1)...(m + 1) where i + len <= n {
                        let slice = Array(recognized[i..<(i + len)])
                        let raw = PhonemeAligner.normalizedCost(target: variant,
                                                                actual: slice) * Double(m)
                        let total = dp[i] + raw + perWordPenalty + freqPenalty
                        if total < dp[i + len] {
                            dp[i + len] = total
                            back[i + len] = (entry.word, i)
                        }
                    }
                }
            }
        }

        guard dp[n] < .infinity else { return nil }

        var words: [String] = []
        var pos = n
        while pos > 0 {
            guard let b = back[pos] else { return nil }
            words.append(b.word)
            pos = b.from
        }
        words.reverse()

        // Quality gate on the pure matching cost (penalties excluded).
        let penalties = words.reduce(0.0) { sum, _ in sum + perWordPenalty }
        let matchCost = dp[n] - penalties
        guard matchCost / Double(n) <= maxAverageCost else { return nil }

        return words
    }
}
