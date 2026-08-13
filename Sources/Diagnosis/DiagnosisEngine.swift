import Foundation

/// A single diagnosed problem, with Korean-specific guidance when available.
struct DiagnosedIssue: Identifiable {
    let id = UUID()
    let op: PhonemeOp
    let title: String
    let explanation: String
    let howToFix: String
    let isKnownKoreanPattern: Bool
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
}

enum DiagnosisEngine {

    /// Diagnose against all pronunciation variants; keep the closest one.
    static func diagnose(word: String,
                         variants: [[String]],
                         recognized: [String],
                         usedMock: Bool) -> DiagnosisReport {
        let target = variants.min {
            PhonemeAligner.normalizedCost(target: $0, actual: recognized)
                < PhonemeAligner.normalizedCost(target: $1, actual: recognized)
        } ?? []

        let ops = PhonemeAligner.align(target: target, actual: recognized)
        var issues: [DiagnosedIssue] = []
        var penalty = 0.0

        let lastTargetIdx = ops.lastIndex(where: { $0.target != nil })

        for (idx, op) in ops.enumerated() {
            guard op.kind != .match else { continue }

            // Allophones of the target are not errors (flap for t/d, glottal for t).
            if op.kind == .substitute, let t = op.target, let a = op.actual,
               PhonemeMapping.substitutionCost(t, a) <= 0.2 { continue }

            // Word-final voicing-only mismatch (s/z, t/d…): the model can't
            // hear final voicing reliably — skip rather than risk a false flag.
            if op.kind == .substitute, idx == lastTargetIdx,
               let t = op.target, let a = op.actual,
               PhonemeMapping.isVoicingOnlyPair(t, a) { continue }

            switch op.kind {
            case .substitute:
                let c = PhonemeMapping.substitutionCost(op.target ?? "", op.actual ?? "")
                penalty += min(c / 1.8, 1.0)
            case .delete, .insert:
                penalty += 0.8
            case .match:
                break
            }

            if let rule = KoreanL1Rules.match(op) {
                // Word-final vowel epenthesis gets the more specific explanation.
                if rule.id == "vowel-epenthesis", idx == ops.count - 1,
                   let finalRelease = KoreanL1Rules.all.first(where: { $0.id == "final-release" }) {
                    issues.append(DiagnosedIssue(op: op, title: finalRelease.title,
                                                 explanation: finalRelease.explanation,
                                                 howToFix: finalRelease.howToFix,
                                                 isKnownKoreanPattern: true))
                } else {
                    issues.append(DiagnosedIssue(op: op, title: rule.title,
                                                 explanation: rule.explanation,
                                                 howToFix: rule.howToFix,
                                                 isKnownKoreanPattern: true))
                }
            } else {
                issues.append(genericIssue(for: op))
            }
        }

        let score = target.isEmpty ? 0
            : Int((max(0.0, 1.0 - penalty / Double(target.count)) * 100).rounded())
        return DiagnosisReport(word: word, targetIPA: target, recognizedIPA: recognized,
                               ops: ops, issues: issues, score: score, usedMockRecognizer: usedMock)
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
