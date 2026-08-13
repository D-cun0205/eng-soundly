import Foundation

/// Picks practice words for a target phoneme from the frequency-ordered
/// lexicon: common, pronounceable-length words that contain the sound.
enum DrillBuilder {

    /// Frequency-ordered drill words containing `phoneme` in their primary
    /// pronunciation. Prefers short-ish words (3–8 phonemes) so the drill
    /// isolates the target sound.
    static func words(containing phoneme: String,
                      lexicon: [CandidateRanker.Entry],
                      limit: Int = 8) -> [String] {
        var result: [String] = []
        for entry in lexicon {
            guard let primary = entry.variants.first,
                  (3...8).contains(primary.count),
                  primary.contains(phoneme) else { continue }
            result.append(entry.word)
            if result.count == limit { break }
        }
        return result
    }
}
