import Foundation

/// One aligned step between target and actual phoneme sequences.
struct PhonemeOp: Identifiable, Equatable {
    enum Kind: Equatable { case match, substitute, delete, insert }
    let id = UUID()
    let kind: Kind
    let target: String?   // nil for insert
    let actual: String?   // nil for delete

    static func == (l: PhonemeOp, r: PhonemeOp) -> Bool {
        l.kind == r.kind && l.target == r.target && l.actual == r.actual
    }
}

/// Needleman–Wunsch global alignment over phoneme strings, with
/// phonetic-feature-based substitution costs so that plausible confusions
/// pair up instead of producing spurious delete+insert pairs.
enum PhonemeAligner {
    static let gapCost = 0.9

    static func align(target: [String], actual: [String]) -> [PhonemeOp] {
        let n = target.count, m = actual.count
        if n == 0 { return actual.map { PhonemeOp(kind: .insert, target: nil, actual: $0) } }
        if m == 0 { return target.map { PhonemeOp(kind: .delete, target: $0, actual: nil) } }

        var cost = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { cost[i][0] = Double(i) * gapCost }
        for j in 1...m { cost[0][j] = Double(j) * gapCost }

        for i in 1...n {
            for j in 1...m {
                let sub = cost[i-1][j-1] + PhonemeMapping.substitutionCost(target[i-1], actual[j-1])
                let del = cost[i-1][j] + gapCost
                let ins = cost[i][j-1] + gapCost
                cost[i][j] = min(sub, del, ins)
            }
        }

        // Backtrack
        var ops: [PhonemeOp] = []
        var i = n, j = m
        while i > 0 || j > 0 {
            if i > 0 && j > 0 {
                let sub = cost[i-1][j-1] + PhonemeMapping.substitutionCost(target[i-1], actual[j-1])
                if abs(cost[i][j] - sub) < 1e-9 {
                    let kind: PhonemeOp.Kind = target[i-1] == actual[j-1] ? .match : .substitute
                    ops.append(PhonemeOp(kind: kind, target: target[i-1], actual: actual[j-1]))
                    i -= 1; j -= 1
                    continue
                }
            }
            if i > 0 && abs(cost[i][j] - (cost[i-1][j] + gapCost)) < 1e-9 {
                ops.append(PhonemeOp(kind: .delete, target: target[i-1], actual: nil))
                i -= 1
            } else {
                ops.append(PhonemeOp(kind: .insert, target: nil, actual: actual[j-1]))
                j -= 1
            }
        }
        return ops.reversed()
    }

    /// Total alignment cost normalized by target length (0 = perfect).
    static func normalizedCost(target: [String], actual: [String]) -> Double {
        let n = target.count, m = actual.count
        if n == 0 { return m == 0 ? 0 : Double(m) }
        var cost = [[Double]](repeating: [Double](repeating: 0, count: m + 1), count: n + 1)
        for i in 1...n { cost[i][0] = Double(i) * gapCost }
        if m > 0 { for j in 1...m { cost[0][j] = Double(j) * gapCost } }
        if m > 0 {
            for i in 1...n {
                for j in 1...m {
                    let sub = cost[i-1][j-1] + PhonemeMapping.substitutionCost(target[i-1], actual[j-1])
                    cost[i][j] = min(sub, cost[i-1][j] + gapCost, cost[i][j-1] + gapCost)
                }
            }
        }
        return cost[n][m] / Double(n)
    }
}
