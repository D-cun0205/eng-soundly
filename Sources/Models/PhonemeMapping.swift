import Foundation

/// Canonical IPA phoneme set used throughout the app (General American English).
/// Both CMUdict targets (ARPAbet) and recognizer output (espeak IPA) are
/// normalized into this set before alignment / diagnosis.
enum PhonemeMapping {

    // MARK: - ARPAbet → canonical IPA

    /// Maps a single ARPAbet token (with optional stress digit) to canonical IPA.
    /// AH0 (unstressed) → ə, AH1/AH2 → ʌ. Stress digits otherwise dropped.
    static func arpabetToIPA(_ token: String) -> String? {
        let stress = token.last.flatMap { $0.isNumber ? $0 : nil }
        let base = token.trimmingCharacters(in: .decimalDigits)
        if base == "AH" { return stress == "0" ? "ə" : "ʌ" }
        return arpabetTable[base]
    }

    private static let arpabetTable: [String: String] = [
        "AA": "ɑ", "AE": "æ", "AO": "ɔ", "AW": "aʊ", "AY": "aɪ",
        "B": "b", "CH": "tʃ", "D": "d", "DH": "ð",
        "EH": "ɛ", "ER": "ɚ", "EY": "eɪ",
        "F": "f", "G": "ɡ", "HH": "h",
        "IH": "ɪ", "IY": "i", "JH": "dʒ",
        "K": "k", "L": "l", "M": "m", "N": "n", "NG": "ŋ",
        "OW": "oʊ", "OY": "ɔɪ",
        "P": "p", "R": "ɹ", "S": "s", "SH": "ʃ",
        "T": "t", "TH": "θ",
        "UH": "ʊ", "UW": "u",
        "V": "v", "W": "w", "Y": "j", "Z": "z", "ZH": "ʒ",
    ]

    // MARK: - espeak IPA → canonical IPA

    /// Normalizes a raw recognizer token (espeak-style IPA, possibly with
    /// length marks / diacritics / non-English phones) into the canonical set.
    /// Returns nil for tokens that should be dropped (stress marks, specials).
    static func normalizeRecognized(_ raw: String) -> String? {
        if raw.isEmpty { return nil }
        // Special / non-phonemic tokens
        if ["<pad>", "<s>", "</s>", "<unk>", "|", " ", "ˈ", "ˌ"].contains(raw) { return nil }

        // Strip stress marks, length marks and combining diacritics.
        var s = raw
        let strippable: Set<Character> = ["ˈ", "ˌ", "ː", "ˑ", "̃", "̩", "̯", "̪", "ʲ", "ʰ", "̥", "͡"]
        s = String(s.filter { !strippable.contains($0) })
        if s.isEmpty { return nil }

        if canonicalSet.contains(s) { return s }
        if let mapped = espeakRemap[s] { return mapped }

        // Multi-char cluster not in table: try char-by-char first element remap
        // (better to keep something than drop it — aligner handles the rest).
        return s
    }

    /// Remaps espeak-specific or non-English phones to the nearest canonical phoneme.
    private static let espeakRemap: [String: String] = [
        "a": "æ", "ɐ": "ʌ", "ä": "ɑ", "ɑ": "ɑ",
        "e": "ɛ", "o": "oʊ", "ɜ": "ɚ", "ɝ": "ɚ", "ɵ": "oʊ",
        "y": "u", "ø": "oʊ", "œ": "ɚ", "ɶ": "æ",
        "ɨ": "ɪ", "ʉ": "u", "ɯ": "u", "ɤ": "ʌ", "ɒ": "ɑ",
        "r": "ɹ", "ɾ": "ɾ", "ɫ": "l", "ʎ": "l", "ʝ": "j",
        "g": "ɡ", "q": "k", "x": "h", "χ": "h", "ħ": "h", "ɦ": "h",
        "β": "v", "ɸ": "f", "ç": "h",
        "ʈ": "t", "ɖ": "d", "ɳ": "n", "ɲ": "n", "ɴ": "ŋ",
        "ʋ": "v", "ɻ": "ɹ", "ɽ": "ɾ",
        "ts": "ts", "dz": "z", "tɕ": "tʃ", "dʑ": "dʒ", "ɕ": "ʃ", "ʑ": "ʒ",
        "əl": "l", "ən": "n", "əm": "m",
        "ʌʊ": "oʊ", "ɛɪ": "eɪ", "ɔɪ": "ɔɪ", "əʊ": "oʊ", "ɑɪ": "aɪ", "ɑʊ": "aʊ",
        "iə": "i", "eə": "ɛ", "ʊə": "ʊ",
    ]

    /// The canonical phoneme inventory (GA English) + a few allophones we keep
    /// because they carry diagnostic meaning (ɾ flap, ʔ glottal stop).
    static let canonicalSet: Set<String> = [
        // vowels
        "i", "ɪ", "ɛ", "æ", "ɑ", "ɔ", "ʊ", "u", "ʌ", "ə", "ɚ",
        // diphthongs
        "eɪ", "aɪ", "ɔɪ", "aʊ", "oʊ",
        // consonants
        "p", "b", "t", "d", "k", "ɡ", "tʃ", "dʒ",
        "f", "v", "θ", "ð", "s", "z", "ʃ", "ʒ", "h",
        "m", "n", "ŋ", "l", "ɹ", "j", "w",
        // allophones kept for diagnosis
        "ɾ", "ʔ",
    ]

    // MARK: - Phonetic features (for alignment cost)

    struct Features {
        enum Kind { case vowel, consonant }
        let kind: Kind
        // consonant features
        var voiced: Bool = false
        var place: Int = 0     // 0 bilabial … 8 glottal
        var manner: Int = 0    // 0 stop, 1 affricate, 2 fricative, 3 nasal, 4 liquid, 5 glide, 6 flap
        // vowel features
        var height: Int = 0    // 0 high … 3 low
        var backness: Int = 0  // 0 front … 2 back
        var rounded: Bool = false
        var rhotic: Bool = false
        var diphthong: Bool = false
    }

    static let features: [String: Features] = [
        // vowels: height(0 high–3 low), backness(0 front–2 back)
        "i": .init(kind: .vowel, height: 0, backness: 0),
        "ɪ": .init(kind: .vowel, height: 0, backness: 0),
        "ɛ": .init(kind: .vowel, height: 1, backness: 0),
        "æ": .init(kind: .vowel, height: 2, backness: 0),
        "ɑ": .init(kind: .vowel, height: 3, backness: 2),
        "ɔ": .init(kind: .vowel, height: 2, backness: 2, rounded: true),
        "ʊ": .init(kind: .vowel, height: 0, backness: 2, rounded: true),
        "u": .init(kind: .vowel, height: 0, backness: 2, rounded: true),
        "ʌ": .init(kind: .vowel, height: 1, backness: 1),
        "ə": .init(kind: .vowel, height: 1, backness: 1),
        "ɚ": .init(kind: .vowel, height: 1, backness: 1, rhotic: true),
        "eɪ": .init(kind: .vowel, height: 1, backness: 0, diphthong: true),
        "aɪ": .init(kind: .vowel, height: 3, backness: 1, diphthong: true),
        "ɔɪ": .init(kind: .vowel, height: 2, backness: 2, rounded: true, diphthong: true),
        "aʊ": .init(kind: .vowel, height: 3, backness: 1, diphthong: true),
        "oʊ": .init(kind: .vowel, height: 1, backness: 2, rounded: true, diphthong: true),
        // consonants: place 0 bilabial,1 labiodental,2 dental,3 alveolar,4 postalveolar,5 palatal,6 velar,7 labiovelar,8 glottal
        "p": .init(kind: .consonant, voiced: false, place: 0, manner: 0),
        "b": .init(kind: .consonant, voiced: true, place: 0, manner: 0),
        "t": .init(kind: .consonant, voiced: false, place: 3, manner: 0),
        "d": .init(kind: .consonant, voiced: true, place: 3, manner: 0),
        "k": .init(kind: .consonant, voiced: false, place: 6, manner: 0),
        "ɡ": .init(kind: .consonant, voiced: true, place: 6, manner: 0),
        "ʔ": .init(kind: .consonant, voiced: false, place: 8, manner: 0),
        "tʃ": .init(kind: .consonant, voiced: false, place: 4, manner: 1),
        "dʒ": .init(kind: .consonant, voiced: true, place: 4, manner: 1),
        "f": .init(kind: .consonant, voiced: false, place: 1, manner: 2),
        "v": .init(kind: .consonant, voiced: true, place: 1, manner: 2),
        "θ": .init(kind: .consonant, voiced: false, place: 2, manner: 2),
        "ð": .init(kind: .consonant, voiced: true, place: 2, manner: 2),
        "s": .init(kind: .consonant, voiced: false, place: 3, manner: 2),
        "z": .init(kind: .consonant, voiced: true, place: 3, manner: 2),
        "ʃ": .init(kind: .consonant, voiced: false, place: 4, manner: 2),
        "ʒ": .init(kind: .consonant, voiced: true, place: 4, manner: 2),
        "h": .init(kind: .consonant, voiced: false, place: 8, manner: 2),
        "m": .init(kind: .consonant, voiced: true, place: 0, manner: 3),
        "n": .init(kind: .consonant, voiced: true, place: 3, manner: 3),
        "ŋ": .init(kind: .consonant, voiced: true, place: 6, manner: 3),
        "l": .init(kind: .consonant, voiced: true, place: 3, manner: 4),
        "ɹ": .init(kind: .consonant, voiced: true, place: 3, manner: 4),
        "ɾ": .init(kind: .consonant, voiced: true, place: 3, manner: 6),
        "j": .init(kind: .consonant, voiced: true, place: 5, manner: 5),
        "w": .init(kind: .consonant, voiced: true, place: 7, manner: 5),
    ]

    /// Substitution cost between two canonical phonemes for alignment (0…2).
    static func substitutionCost(_ a: String, _ b: String) -> Double {
        if a == b { return 0 }
        guard let fa = features[a], let fb = features[b] else { return 1.5 }

        // flap ↔ t/d : near-free (allophone)
        if (a == "ɾ" && (b == "t" || b == "d")) || (b == "ɾ" && (a == "t" || a == "d")) { return 0.15 }
        // glottal stop ↔ t : near-free (allophone)
        if (a == "ʔ" && b == "t") || (b == "ʔ" && a == "t") { return 0.15 }
        // ɑ ↔ ɔ : cot–caught merger — most GA speakers (and the acoustic
        // model) realize dictionary /ɔ/ as [ɑ]; never flag this as an error.
        if Set([a, b]) == Set(["ɑ", "ɔ"]) { return 0.15 }

        if fa.kind != fb.kind {
            // glide ↔ high vowel is plausible (w~u, j~i)
            let glidePairs: Set<Set<String>> = [["w", "u"], ["w", "ʊ"], ["j", "i"], ["j", "ɪ"]]
            if glidePairs.contains([a, b]) { return 0.8 }
            return 2.0
        }
        if fa.kind == .vowel {
            var d = 0.0
            d += Double(abs(fa.height - fb.height)) * 0.30
            d += Double(abs(fa.backness - fb.backness)) * 0.30
            if fa.rounded != fb.rounded { d += 0.15 }
            if fa.rhotic != fb.rhotic { d += 0.35 }
            if fa.diphthong != fb.diphthong { d += 0.25 }
            return min(max(d, 0.25), 1.8)
        } else {
            var d = 0.0
            d += Double(abs(fa.place - fb.place)) * 0.18
            d += Double(abs(fa.manner - fb.manner)) * 0.30
            if fa.voiced != fb.voiced { d += 0.25 }
            return min(max(d, 0.25), 1.8)
        }
    }

    /// True when two consonants differ ONLY in voicing (s/z, t/d, f/v, …).
    /// Word-finally the acoustic model cannot hear this distinction reliably,
    /// so diagnosis treats such word-final pairs as low-confidence and skips them.
    static func isVoicingOnlyPair(_ a: String, _ b: String) -> Bool {
        guard let fa = features[a], let fb = features[b],
              fa.kind == .consonant, fb.kind == .consonant else { return false }
        return fa.place == fb.place && fa.manner == fb.manner && fa.voiced != fb.voiced
    }

    /// Human-readable Korean articulation description, used for generic feedback.
    static let koreanDescription: [String: String] = [
        "θ": "혀끝을 윗니 아래에 살짝 대고 바람을 내보내는 무성음 (번데기 발음)",
        "ð": "θ와 같은 위치에서 성대를 울리는 유성음",
        "f": "윗니를 아랫입술에 대고 바람을 내보내는 소리",
        "v": "f와 같은 위치에서 성대를 울리는 소리",
        "ɹ": "혀끝을 어디에도 닿지 않게 뒤로 말아 내는 소리",
        "l": "혀끝을 윗잇몸에 확실히 붙이고 내는 소리",
        "z": "s 위치에서 성대를 울리는 소리 (혀가 잇몸에 닿지 않음)",
        "ʃ": "입술을 앞으로 내밀고 내는 '쉬' 소리",
        "ʒ": "ʃ의 유성음 버전",
        "æ": "입을 크게 벌리고 '애'보다 낮고 넓게 내는 소리",
        "ɛ": "한국어 '에'와 비슷하지만 입이 조금 더 열린 소리",
        "ɪ": "'이'와 '에' 사이의 짧고 느슨한 소리",
        "i": "입꼬리를 당겨 길게 내는 긴장된 '이'",
        "ʊ": "'우'와 '어' 사이의 짧고 느슨한 소리",
        "u": "입술을 둥글게 내밀어 내는 긴장된 '우'",
        "ɚ": "혀를 말아 올린 채 내는 '어r' 소리",
        "ə": "힘을 완전히 뺀 짧은 '어' (약화 모음)",
        "ŋ": "받침 'ㅇ' 소리 — 뒤에 ɡ를 붙이지 않도록 주의",
        "w": "입술을 확실히 둥글게 오므렸다가 펴면서 내는 소리",
    ]
}
