import Foundation

/// One connected-speech phenomenon detected in a sentence: a way a native
/// speaker would naturally contract or link these words. Applying it keeps
/// per-word slots so word attribution survives.
struct LiaisonTransform {
    let id: String
    let title: String        // short Korean label, e.g. "want to → wanna"
    let tip: String          // how/why, in Korean
    let wordIndices: [Int]   // which words it touches
    let apply: ([[String]]) -> [[String]]
}

/// A liaison note in the final report: either the user already produced the
/// natural connected form (achieved) or it's an opportunity to sound more
/// natural (suggestion). Never an error — careful speech is correct speech.
struct LiaisonTip: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let achieved: Bool
}

enum LiaisonRules {

    // MARK: - Weak forms (single-word extra variants, no coordination needed)

    /// Reduced function-word forms used in running speech, appended to the
    /// dictionary variants before variant selection.
    static let weakForms: [String: [[String]]] = [
        "and": [["ə", "n"], ["n"]],
        "of": [["ə"]],
        "can": [["k", "ə", "n"]],
        "you": [["j", "ə"]],
        "your": [["j", "ɚ"]],
        "for": [["f", "ɚ"]],
        "or": [["ɚ"]],
        "them": [["ə", "m"]],
        "us": [["ə", "s"]],
    ]

    // MARK: - Word-pair contractions

    /// (first word, second word) → (replacement phonemes for each slot).
    private static let contractions: [String: (first: [String], second: [String], spoken: String)] = [
        "want to": (["w", "ɑ", "n"], ["ə"], "wanna"),
        "going to": (["ɡ", "ə", "n"], ["ə"], "gonna"),
        "got to": (["ɡ", "ɑ", "ɾ"], ["ə"], "gotta"),
        "have to": (["h", "æ", "f"], ["t", "ə"], "hafta"),
        "has to": (["h", "æ", "s"], ["t", "ə"], "hasta"),
        "kind of": (["k", "aɪ", "n"], ["ə"], "kinda"),
        "out of": (["aʊ", "ɾ"], ["ə"], "outta"),
        "don't know": (["d", "ə"], ["n", "oʊ"], "dunno"),
        "let me": (["l", "ɛ"], ["m", "i"], "lemme"),
        "give me": (["ɡ", "ɪ"], ["m", "i"], "gimme"),
    ]

    private static let palatalization: [String: (String, String)] = [
        "t": ("tʃ", "t + y → ch(ʧ)"),
        "d": ("dʒ", "d + y → j(ʤ)"),
        "s": ("ʃ", "s + y → sh(ʃ)"),
        "z": ("ʒ", "z + y → ʒ"),
    ]

    private static let hDropWords: Set<String> = ["he", "him", "his", "her", "hers"]

    // MARK: - Detection

    /// All connected-speech transforms applicable to this sentence, given
    /// the currently chosen per-word phonemes.
    static func transforms(words: [String], combo: [[String]]) -> [LiaisonTransform] {
        guard words.count == combo.count, words.count > 1 else { return [] }
        var found: [LiaisonTransform] = []

        for i in 0..<(words.count - 1) {
            let w1 = words[i], w2 = words[i + 1]
            let p1 = combo[i], p2 = combo[i + 1]
            guard let last = p1.last, let first = p2.first else { continue }

            // 1. Lexical contractions (wanna, gonna, …)
            if let c = contractions["\(w1) \(w2)"] {
                found.append(LiaisonTransform(
                    id: "contraction-\(i)",
                    title: "\(w1) \(w2) → \(c.spoken)",
                    tip: "원어민은 일상 대화에서 '\(w1) \(w2)'를 '\(c.spoken)'처럼 축약해요.",
                    wordIndices: [i, i + 1],
                    apply: { combo in
                        var out = combo
                        out[i] = c.first
                        out[i + 1] = c.second
                        return out
                    }))
            }

            // 2. Palatalization: t/d/s/z + y-initial word (did you → 디쥬)
            if first == "j", let (merged, desc) = palatalization[last] {
                found.append(LiaisonTransform(
                    id: "palatal-\(i)",
                    title: "\(w1) + \(w2) 연음",
                    tip: "\(desc): '\(w1) \(w2)'는 소리가 합쳐져 한 덩어리로 이어져요.",
                    wordIndices: [i, i + 1],
                    apply: { combo in
                        var out = combo
                        out[i] = Array(out[i].dropLast()) + [merged]
                        out[i + 1] = Array(out[i + 1].dropFirst())
                        return out
                    }))
            }

            // 3. t/d elision between consonants (best friend → bes' friend)
            if (last == "t" || last == "d"), p1.count >= 2,
               PhonemeMapping.features[p1[p1.count - 2]]?.kind == .consonant,
               PhonemeMapping.features[first]?.kind == .consonant, first != "j" {
                found.append(LiaisonTransform(
                    id: "elision-\(i)",
                    title: "\(w1)의 끝 \(last) 약화",
                    tip: "자음 사이에 낀 t/d는 살짝 삼켜요: '\(w1) \(w2)'에서 \(last)를 거의 발음하지 않아요.",
                    wordIndices: [i],
                    apply: { combo in
                        var out = combo
                        out[i] = Array(out[i].dropLast())
                        return out
                    }))
            }

            // 4. h-dropping in unstressed pronouns (tell him → 텔림)
            if hDropWords.contains(w2), first == "h" {
                found.append(LiaisonTransform(
                    id: "hdrop-\(i + 1)",
                    title: "\(w2)의 h 약화",
                    tip: "문장 중간의 \(w2)는 h가 약해져 앞 단어와 이어져요: '\(w1) \(w2)'가 한 덩어리처럼 들려요.",
                    wordIndices: [i + 1],
                    apply: { combo in
                        var out = combo
                        out[i + 1] = Array(out[i + 1].dropFirst())
                        return out
                    }))
            }

            // 5. Geminate merge: same consonant meets itself (gas station)
            if last == first, PhonemeMapping.features[last]?.kind == .consonant {
                found.append(LiaisonTransform(
                    id: "geminate-\(i)",
                    title: "\(w1)·\(w2) 같은 자음 연결",
                    tip: "같은 자음이 만나면 두 번 발음하지 않고 한 번만 길게 이어요.",
                    wordIndices: [i],
                    apply: { combo in
                        var out = combo
                        out[i] = Array(out[i].dropLast())
                        return out
                    }))
            }
        }
        return found
    }
}
