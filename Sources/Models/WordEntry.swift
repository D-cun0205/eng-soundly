import Foundation

/// A category of Korean-L1 pronunciation difficulty, with its practice words.
struct WordCategory: Identifiable, Decodable {
    let id: String
    let title: String        // Korean label
    let subtitle: String     // what to watch for
    let words: [WordEntry]
}

struct WordEntry: Identifiable, Decodable {
    var id: String { word }
    let word: String
    let meaning: String      // Korean gloss
    let contrast: String?    // minimal-pair partner, if any

    enum CodingKeys: String, CodingKey { case word, meaning, contrast }
}

enum WordCatalog {
    static func load() -> [WordCategory] {
        guard let url = Bundle.main.url(forResource: "words", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let categories = try? JSONDecoder().decode([WordCategory].self, from: data)
        else { return [] }
        return categories
    }
}
