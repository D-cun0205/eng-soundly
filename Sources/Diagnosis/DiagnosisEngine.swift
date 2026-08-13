import Foundation

/// A single diagnosed problem, with Korean-specific guidance when available.
struct DiagnosedIssue: Identifiable {
    let id = UUID()
    let op: PhonemeOp
    let title: String
    let explanation: String
    let howToFix: String
    let isKnownKoreanPattern: Bool
    /// The word this issue belongs to (sentence mode; nil for single words).
    var word: String?
}

/// Per-word result inside a sentence attempt.
struct WordScore: Identifiable {
    let id = UUID()
    let word: String
    let score: Int          // 0…100
}

/// One word of a sentence target with its pronunciation variants.
struct WordTarget {
    let word: String
    let variants: [[String]]
}

/// Full result of one practice attempt.
struct DiagnosisReport {
    let word: String
    let targetIPA: [String]
    let recognizedIPA: [String]
    let ops: [PhonemeOp]
    let issues: [DiagnosedIssue]
    let score: Int          // 0…100
    let usedMockRecognizer: Bool
    /// Per-word breakdown; more than one entry only in sentence mode.
    var wordScores: [WordScore] = []
    /// Connected-speech notes: liaison the user produced (achieved) or
    /// could adopt to sound more natural (suggestions). Never errors.
    var liaisonTips: [LiaisonTip] = []
}

enum DiagnosisEngine {

    /// Substitutions/insertions whose recognized token scored below this are
    /// treated as "not confidently heard" and never flagged: a wrong flag is
    /// worse than a missed one.
    static let confidenceGate: Float = 0.45

    /// Diagnose a single word against all its pronunciation variants.
    /// `confidences[i]` (optional) is the model's confidence in `recognized[i]`.
    static func diagnose(word: String,
                         variants: [[String]],
                         recognized: [String],
                         confidences: [Float]? = nil,
                         usedMock: Bool) -> DiagnosisReport {
        diagnose(sentence: [WordTarget(word: word, variants: variants)],
                 displayText: word, recognized: recognized,
                 confidences: confidences, usedMock: usedMock)
    }

    /// Diagnose a sentence: one WordTarget per word, in order. The target is
    /// the best-matching combination of per-word variants; every op is
    /// attributed to a word so the report carries per-word scores.
    static func diagnose(sentence: [WordTarget],
                         displayText: String? = nil,
                         recognized: [String],
                         confidences: [Float]? = nil,
                         usedMock: Bool) -> DiagnosisReport {
        // In sentences, function words also carry their reduced (weak) forms:
        // careful /æ n d/ and running-speech /ə n/ are both correct.
        let sentence = sentence.count > 1
            ? sentence.map { wt in
                LiaisonRules.weakForms[wt.word].map {
                    WordTarget(word: wt.word, variants: wt.variants + $0)
                } ?? wt
            }
            : sentence
        // Pick the pronunciation variant per word by coordinate descent:
        // start from every word's primary form, then repeatedly swap in the
        // single alternate that lowers the whole-utterance alignment cost.
        // Unlike enumerating combinations this never truncates a word's
        // variant list ("to" really is /tə/ in running speech — its third
        // dictionary form), and it costs O(variants · passes) alignments.
        var bestCombo = sentence.map { $0.variants.first ?? [] }
        var bestCost = PhonemeAligner.normalizedCost(target: bestCombo.flatMap { $0 },
                                                     actual: recognized)
        for _ in 0..<3 {
            var improved = false
            for (w, wt) in sentence.enumerated() where wt.variants.count > 1 {
                for variant in wt.variants.dropFirst() {
                    var trial = bestCombo
                    trial[w] = variant
                    let cost = PhonemeAligner.normalizedCost(target: trial.flatMap { $0 },
                                                             actual: recognized)
                    if cost < bestCost {
                        bestCombo = trial
                        bestCost = cost
                        improved = true
                    }
                }
            }
            if !improved { break }
        }

        // Connected-speech pass: try each natural contraction/link. If the
        // audio matches the linked form better, the speaker used liaison —
        // praise it. If the careful form fits better, that's NOT an error;
        // surface the liaison as a naturalness tip instead.
        var liaisonTips: [LiaisonTip] = []
        if sentence.count > 1 {
            let transforms = LiaisonRules.transforms(words: sentence.map(\.word),
                                                     combo: bestCombo)
            // Several rules can fire on the same boundary (wanna also implies
            // t-elision); report at most one tip per word, rule order = priority.
            var tippedWords = Set<Int>()
            for transform in transforms {
                guard tippedWords.isDisjoint(with: transform.wordIndices) else { continue }
                let trial = transform.apply(bestCombo)
                let cost = PhonemeAligner.normalizedCost(target: trial.flatMap { $0 },
                                                         actual: recognized)
                if cost < bestCost {
                    bestCombo = trial
                    bestCost = cost
                    liaisonTips.append(LiaisonTip(
                        title: transform.title,
                        detail: "원어민처럼 자연스럽게 이어 발음했어요!",
                        achieved: true))
                } else {
                    liaisonTips.append(LiaisonTip(title: transform.title,
                                                  detail: transform.tip,
                                                  achieved: false))
                }
                tippedWords.formUnion(transform.wordIndices)
            }
            // Keep every achievement; don't overwhelm with suggestions.
            let achieved = liaisonTips.filter(\.achieved)
            let suggested = liaisonTips.filter { !$0.achieved }.prefix(3)
            liaisonTips = achieved + suggested
        }

        // Word boundaries inside the flattened target.
        var ranges: [Range<Int>] = []
        var pos = 0
        for wordPhonemes in bestCombo {
            ranges.append(pos..<(pos + wordPhonemes.count))
            pos += wordPhonemes.count
        }
        let target = bestCombo.flatMap { $0 }
        let wordFinalIdxs = Set(ranges.compactMap { $0.isEmpty ? nil : $0.upperBound - 1 })

        func wordIndex(forTargetIdx t: Int) -> Int {
            ranges.firstIndex { $0.contains(t) } ?? max(0, sentence.count - 1)
        }

        let ops = PhonemeAligner.align(target: target, actual: recognized)
        var issues: [DiagnosedIssue] = []
        var wordPenalties = [Double](repeating: 0, count: sentence.count)

        var tIdx = -1      // index into `target` for ops that consume a target phoneme
        var actualIdx = -1 // index into `recognized` for ops that consume a token

        for op in ops {
            if op.target != nil { tIdx += 1 }
            if op.actual != nil { actualIdx += 1 }
            guard op.kind != .match else { continue }

            // Low-confidence evidence: don't flag, don't penalize.
            if op.actual != nil, let confidences,
               actualIdx < confidences.count,
               confidences[actualIdx] < Self.confidenceGate { continue }

            // Allophones of the target are not errors (flap for t/d, glottal for t).
            if op.kind == .substitute, let t = op.target, let a = op.actual,
               PhonemeMapping.substitutionCost(t, a) <= 0.2 { continue }

            // Word-final voicing-only mismatch (s/z, t/d…): the model can't
            // hear final voicing reliably — skip rather than risk a false flag.
            if op.kind == .substitute, wordFinalIdxs.contains(tIdx),
               let t = op.target, let a = op.actual,
               PhonemeMapping.isVoicingOnlyPair(t, a) { continue }

            // Attribute the op to a word: by target position, or for pure
            // insertions to the word of the last consumed target phoneme.
            let wordIdx = wordIndex(forTargetIdx: max(tIdx, 0))
            let wordLabel = sentence.count > 1 ? sentence[wordIdx].word : nil

            switch op.kind {
            case .substitute:
                let c = PhonemeMapping.substitutionCost(op.target ?? "", op.actual ?? "")
                wordPenalties[wordIdx] += min(c / 1.8, 1.0)
            case .delete, .insert:
                wordPenalties[wordIdx] += 0.8
            case .match:
                break
            }

            // Word-final vowel epenthesis gets the more specific explanation.
            let isWordFinalContext = tIdx < 0 || wordFinalIdxs.contains(tIdx)
            if let rule = KoreanL1Rules.match(op) {
                if rule.id == "vowel-epenthesis", isWordFinalContext, op.kind == .insert,
                   let finalRelease = KoreanL1Rules.all.first(where: { $0.id == "final-release" }) {
                    issues.append(DiagnosedIssue(op: op, title: finalRelease.title,
                                                 explanation: finalRelease.explanation,
                                                 howToFix: finalRelease.howToFix,
                                                 isKnownKoreanPattern: true, word: wordLabel))
                } else {
                    issues.append(DiagnosedIssue(op: op, title: rule.title,
                                                 explanation: rule.explanation,
                                                 howToFix: rule.howToFix,
                                                 isKnownKoreanPattern: true, word: wordLabel))
                }
            } else {
                var issue = genericIssue(for: op)
                issue.word = wordLabel
                issues.append(issue)
            }
        }

        func scoreFrom(penalty: Double, count: Int) -> Int {
            guard count > 0 else { return 0 }
            return Int((max(0.0, 1.0 - penalty / Double(count)) * 100).rounded())
        }

        let wordScores = zip(sentence, zip(ranges, wordPenalties)).map { wt, rp in
            WordScore(word: wt.word, score: scoreFrom(penalty: rp.1, count: rp.0.count))
        }
        let score = scoreFrom(penalty: wordPenalties.reduce(0, +), count: target.count)
        let title = displayText ?? sentence.map(\.word).joined(separator: " ")

        return DiagnosisReport(word: title, targetIPA: target, recognizedIPA: recognized,
                               ops: ops, issues: issues, score: score,
                               usedMockRecognizer: usedMock, wordScores: wordScores,
                               liaisonTips: liaisonTips)
    }

    private static func genericIssue(for op: PhonemeOp) -> DiagnosedIssue {
        switch op.kind {
        case .substitute:
            let t = op.target ?? "?", a = op.actual ?? "?"
            let desc = PhonemeMapping.koreanDescription[t].map { "\n\(t): \($0)" } ?? ""
            return DiagnosedIssue(
                op: op,
                title: "\(t)가 \(a)처럼 들렸어요",
                explanation: "목표 소리 \(t) 대신 \(a)에 가까운 소리가 감지되었습니다.\(desc)",
                howToFix: "원어민 발음을 듣고 \(t) 소리에 집중해서 다시 시도해 보세요.",
                isKnownKoreanPattern: false)
        case .delete:
            let t = op.target ?? "?"
            return DiagnosedIssue(
                op: op,
                title: "\(t) 소리가 빠졌어요",
                explanation: "목표 발음에 있는 \(t)가 들리지 않았습니다.",
                howToFix: "천천히 발음하며 \(t)를 의식적으로 포함해 보세요.",
                isKnownKoreanPattern: false)
        case .insert:
            let a = op.actual ?? "?"
            return DiagnosedIssue(
                op: op,
                title: "불필요한 \(a) 소리가 들렸어요",
                explanation: "목표 발음에 없는 \(a)가 추가로 감지되었습니다.",
                howToFix: "음절 수를 원어민 발음과 비교해 보세요. 필요한 소리만 남기고 줄여 봅니다.",
                isKnownKoreanPattern: false)
        case .match:
            fatalError("match ops are not issues")
        }
    }

}
