import Foundation

/// A known Korean-L1 interference pattern, matched against alignment ops.
struct KoreanL1Rule: Identifiable {
    let id: String
    let title: String          // short Korean label
    let explanation: String    // why Korean speakers do this
    let howToFix: String       // articulation guidance
    let matches: (PhonemeOp) -> Bool
}

enum KoreanL1Rules {

    /// Substitution rule helper: matches target→actual (symmetric off).
    private static func sub(_ target: Set<String>, _ actual: Set<String>) -> (PhonemeOp) -> Bool {
        { op in
            op.kind == .substitute
                && op.target.map(target.contains) == true
                && op.actual.map(actual.contains) == true
        }
    }

    static let all: [KoreanL1Rule] = [
        .init(
            id: "r-as-l",
            title: "ɹ을 l처럼 발음",
            explanation: "한국어의 'ㄹ'은 위치에 따라 [l]과 [ɾ]로 소리 나며, 영어의 ɹ에 해당하는 소리가 없습니다. 그래서 r을 'ㄹ'로 대체하기 쉽습니다.",
            howToFix: "혀끝이 입천장 어디에도 닿지 않아야 합니다. 혀를 뒤로 살짝 말고 입술을 조금 둥글게 한 채 소리 내 보세요. '우'를 발음할 때 입 모양에서 시작하면 쉽습니다.",
            matches: sub(["ɹ"], ["l", "ɾ"])
        ),
        .init(
            id: "l-as-r",
            title: "l을 ɹ(또는 ㄹ 탄설음)처럼 발음",
            explanation: "모음 사이의 'ㄹ'은 한국어에서 두드림소리 [ɾ]가 되기 때문에, really 같은 단어의 l이 r처럼 들릴 수 있습니다.",
            howToFix: "혀끝을 윗잇몸(치경)에 확실히 붙였다가 떼면서 발음하세요. l은 혀가 '닿는' 소리, ɹ은 '닿지 않는' 소리입니다.",
            matches: sub(["l"], ["ɹ", "ɾ"])
        ),
        .init(
            id: "f-as-p",
            title: "f를 p(ㅍ)처럼 발음",
            explanation: "한국어에는 f 소리가 없어 외래어 표기에서도 'ㅍ'으로 적습니다 (coffee → 커피).",
            howToFix: "윗니를 아랫입술에 가볍게 대고 그 틈으로 바람을 계속 내보내세요. 입술이 터지는 소리(p)가 아니라 바람이 새는 소리(f)여야 합니다.",
            matches: sub(["f"], ["p", "b", "ɸ"])
        ),
        .init(
            id: "v-as-b",
            title: "v를 b(ㅂ)처럼 발음",
            explanation: "한국어에 v가 없어 'ㅂ'으로 대체됩니다 (video → 비디오).",
            howToFix: "f와 같은 자세(윗니+아랫입술)에서 성대를 울려 주세요. 손을 목에 대면 진동이 느껴져야 합니다.",
            matches: sub(["v"], ["b", "p"])
        ),
        .init(
            id: "th-as-s",
            title: "θ를 s(ㅆ)처럼 발음",
            explanation: "한국어에 θ가 없어 'ㅆ' 또는 'ㄸ'로 대체됩니다 (think → 씽크). think와 sink가 같아져 버립니다.",
            howToFix: "혀끝을 윗니와 아랫니 사이에 살짝 내밀고 바람을 내보내세요. 거울로 혀끝이 이 사이로 보이는지 확인하면 좋습니다.",
            matches: sub(["θ"], ["s", "ʃ", "t"])
        ),
        .init(
            id: "dh-as-d",
            title: "ð를 d(ㄷ)처럼 발음",
            explanation: "this, they의 ð는 한국어에 없어 'ㄷ'으로 대체됩니다 (this → 디스).",
            howToFix: "θ와 같은 위치(혀끝을 이 사이에)에서 성대를 울리며 소리 내세요. d처럼 혀로 잇몸을 치는 소리가 아닙니다.",
            matches: sub(["ð"], ["d", "z"])
        ),
        .init(
            id: "z-as-j",
            title: "z를 dʒ(ㅈ)처럼 발음",
            explanation: "한국어의 'ㅈ'은 파찰음이라 zoo가 '주'처럼 발음되기 쉽습니다.",
            howToFix: "s를 길게 내다가 성대만 울려 보세요 (sss → zzz). 혀가 입천장에 닿아 터지는 순간이 없어야 합니다.",
            matches: sub(["z"], ["dʒ", "tʃ", "s"])
        ),
        .init(
            id: "sh-see-merge",
            title: "ʃ와 s의 혼동",
            explanation: "한국어 'ㅅ'은 '이' 모음 앞에서 [ɕ]로 변해 (시 = shi), see/she 구분이 어려워집니다.",
            howToFix: "s는 혀끝을 아랫니 뒤에 두고 입술을 편 채, ʃ는 입술을 앞으로 내밀고 혀를 살짝 뒤로 빼고 발음하세요.",
            matches: { op in
                op.kind == .substitute &&
                ((op.target == "s" && op.actual == "ʃ") || (op.target == "ʃ" && op.actual == "s"))
            }
        ),
        .init(
            id: "ae-eh-merge",
            title: "æ와 ɛ의 혼동 (애/에)",
            explanation: "현대 한국어에서 'ㅐ'와 'ㅔ'의 구분이 사라져, bad/bed 같은 쌍이 같은 소리가 되기 쉽습니다.",
            howToFix: "æ는 턱을 아래로 크게 벌리고 혀를 낮게 둔 채 발음합니다. ɛ보다 훨씬 입이 크게 열려야 합니다. 거울로 턱 높이를 비교해 보세요.",
            matches: { op in
                op.kind == .substitute &&
                ((op.target == "æ" && ["ɛ", "eɪ"].contains(op.actual ?? "")) ||
                 (op.target == "ɛ" && op.actual == "æ"))
            }
        ),
        .init(
            id: "ih-ee-merge",
            title: "ɪ와 i의 혼동 (긴장/이완 '이')",
            explanation: "한국어 '이'는 하나뿐이라 ship/sheep, sit/seat이 구분되지 않습니다. ɪ는 길이가 아니라 혀와 입술의 '긴장도'가 다른 소리입니다.",
            howToFix: "ɪ는 입술과 혀의 힘을 빼고 '이'와 '에' 사이 느낌으로 짧게 냅니다. i는 입꼬리를 옆으로 당기며 긴장되게 냅니다.",
            matches: { op in
                op.kind == .substitute &&
                ((op.target == "ɪ" && op.actual == "i") || (op.target == "i" && op.actual == "ɪ"))
            }
        ),
        .init(
            id: "uh-oo-merge",
            title: "ʊ와 u의 혼동 (긴장/이완 '우')",
            explanation: "full/fool, pull/pool의 구분입니다. 한국어 '우'는 하나뿐입니다.",
            howToFix: "ʊ는 입술을 크게 내밀지 않고 힘을 뺀 짧은 소리, u는 입술을 확실히 둥글게 내민 긴 소리입니다.",
            matches: { op in
                op.kind == .substitute &&
                ((op.target == "ʊ" && op.actual == "u") || (op.target == "u" && op.actual == "ʊ"))
            }
        ),
        .init(
            id: "vowel-epenthesis",
            title: "불필요한 모음 삽입 (으/어 첨가)",
            explanation: "한국어 음절 구조(자음+모음)의 영향으로 자음군이나 어말 자음 뒤에 '으/어'를 붙이기 쉽습니다 (strike → 스트라이크, 5음절).",
            howToFix: "자음군(st, str, sk 등)은 모음 없이 자음끼리 붙여서 한 번에 발음하세요. 어말 자음은 소리를 터뜨리지 말고 닫기만 해도 됩니다.",
            matches: { op in
                op.kind == .insert && ["ə", "ɯ", "u", "ʊ", "ɨ", "ʌ"].contains(op.actual ?? "")
            }
        ),
        .init(
            id: "final-release",
            title: "받침 소리의 과도한 파열",
            explanation: "영어 어말 파열음(p/t/k/b/d/g)은 살짝만 닫아도 되는데, 이를 강하게 터뜨리면서 뒤에 모음이 따라붙게 됩니다 (cake → 케이크).",
            howToFix: "단어 끝 자음은 입 모양만 만들고 소리를 터뜨리지 않는 연습을 해 보세요.",
            matches: { _ in false } // detected via vowel-epenthesis at word-final position (see DiagnosisEngine)
        ),
        .init(
            id: "w-deletion",
            title: "w 탈락 (우 반모음 약화)",
            explanation: "wood, would처럼 w 뒤에 '우' 계열 모음이 오면 w가 사라지기 쉽습니다.",
            howToFix: "입술을 '우'보다 더 강하게 오므렸다가 빠르게 펴면서 다음 모음으로 이동하세요.",
            matches: { op in op.kind == .delete && op.target == "w" }
        ),
        .init(
            id: "ng-plus-g",
            title: "ŋ 뒤에 ɡ 첨가",
            explanation: "singer를 'sing-ger'처럼 발음하는 패턴입니다. 철자에 g가 보여서 생기는 오류이기도 합니다.",
            howToFix: "ŋ은 받침 'ㅇ'으로 끝내고, 혀 뒷부분을 떼면서 ɡ를 터뜨리지 마세요.",
            matches: { op in op.kind == .insert && op.actual == "ɡ" }
        ),
        .init(
            id: "er-vowel",
            title: "ɚ(r화 모음)의 단순화",
            explanation: "bird, work의 ɚ는 혀를 만 채 내는 모음인데, 한국어식으로 '어'로 단순화되기 쉽습니다 (bird → 버드).",
            howToFix: "'어'를 내는 동안 혀끝을 뒤로 말아 올린 상태를 유지하세요. 모음 전체에 r 색깔이 입혀져야 합니다.",
            matches: sub(["ɚ"], ["ə", "ʌ", "ɑ", "ɔ"])
        ),
    ]

    /// Find the first rule matching an op, if any.
    static func match(_ op: PhonemeOp) -> KoreanL1Rule? {
        all.first { $0.matches(op) }
    }
}
