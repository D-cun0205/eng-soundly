import Foundation

/// Loads CMUdict (ARPAbet) from the bundle and serves canonical-IPA
/// target pronunciations. Words can have multiple variants — e.g. "either".
final class PronunciationDictionary {
    private var entries: [String: [[String]]] = [:]  // word → variants → IPA tokens
    private(set) var isLoaded = false

    func load() {
        guard let url = Bundle.main.url(forResource: "cmudict", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }

        var dict: [String: [[String]]] = [:]
        dict.reserveCapacity(140_000)
        text.enumerateLines { line, _ in
            guard !line.isEmpty, line.first != ";" else { return }
            // Format: "word AR1 PA BET # optional comment", variants as "word(2)"
            let noComment = line.split(separator: "#", maxSplits: 1)[0]
            let parts = noComment.split(separator: " ")
            guard parts.count >= 2 else { return }
            var word = String(parts[0]).lowercased()
            if let paren = word.firstIndex(of: "(") { word = String(word[..<paren]) }
            let ipa = parts.dropFirst().compactMap { PhonemeMapping.arpabetToIPA(String($0)) }
            guard !ipa.isEmpty else { return }
            dict[word, default: []].append(ipa)
        }
        entries = dict
        isLoaded = true
    }

    /// All pronunciation variants for a word, as canonical IPA token arrays.
    func pronunciations(for word: String) -> [[String]] {
        entries[word.lowercased()] ?? []
    }

    /// Primary (first listed) pronunciation.
    func primary(for word: String) -> [String]? {
        pronunciations(for: word).first
    }
}
