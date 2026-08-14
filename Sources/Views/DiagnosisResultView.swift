import SwiftUI

/// Circular score gauge with the number inside; animates on appear.
struct ScoreRing: View {
    let score: Int
    let color: Color

    @State private var progress: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 9)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                    .contentTransition(.numericText())
                Text("점")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 84, height: 84)
        .onAppear {
            withAnimation(.easeOut(duration: 0.7)) {
                progress = Double(score) / 100
            }
        }
    }
}

struct DiagnosisResultView: View {
    let report: DiagnosisReport
    let onPlayReference: () -> Void
    var onPlayUserAudio: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Score header
            HStack(spacing: 16) {
                ScoreRing(score: report.score, color: scoreColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("발음 점수")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(scoreLabel)
                        .font(.headline)
                        .foregroundStyle(scoreColor)
                }
                Spacer()
                if report.usedMockRecognizer {
                    Text("데모")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                }
            }

            // Phoneme-by-phoneme alignment
            VStack(alignment: .leading, spacing: 8) {
                Text("음소 비교")
                    .font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(report.ops) { op in
                            phonemeCell(op)
                        }
                    }
                }
                HStack(spacing: 12) {
                    legend(color: .green, label: "정확")
                    legend(color: .orange, label: "다르게 발음")
                    legend(color: .red, label: "빠짐")
                    legend(color: .purple, label: "추가됨")
                }
                .font(.caption2)
            }

            // Per-word scores (sentence mode)
            if report.wordScores.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    Text("단어별 점수")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(report.wordScores) { ws in
                                VStack(spacing: 2) {
                                    Text(ws.word)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(ws.score)")
                                        .font(.caption.monospacedDigit())
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(wordScoreColor(ws.score).opacity(0.15),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(wordScoreColor(ws.score).opacity(0.5), lineWidth: 1))
                            }
                        }
                    }
                }
            }

            // Connected-speech notes (sentence mode)
            if !report.liaisonTips.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("자연스러운 연음")
                        .font(.headline)
                    ForEach(report.liaisonTips) { tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: tip.achieved ? "checkmark.seal.fill" : "lightbulb.fill")
                                .foregroundStyle(tip.achieved ? .green : .yellow)
                                .font(.subheadline)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tip.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(tip.detail)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background((tip.achieved ? Color.green : Color.yellow).opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            // A/B listening: own recording vs native reference
            HStack(spacing: 12) {
                if let onPlayUserAudio {
                    Button {
                        onPlayUserAudio()
                    } label: {
                        Label("내 발음", systemImage: "person.wave.2")
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    onPlayReference()
                } label: {
                    Label("원어민", systemImage: "speaker.wave.2")
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline)

            // Issues
            if report.issues.isEmpty {
                Label("모든 음소가 목표 발음과 일치합니다! 🎉", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("교정 포인트 \(report.issues.count)개")
                        .font(.headline)
                    ForEach(report.issues) { issue in
                        issueCard(issue)
                    }
                }
            }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 20))
    }

    private var scoreColor: Color {
        wordScoreColor(report.score)
    }

    private var scoreLabel: String {
        switch report.score {
        case 95...: "완벽에 가까워요!"
        case 85..<95: "아주 좋아요"
        case 60..<85: "조금만 더 다듬어요"
        default: "천천히 다시 해봐요"
        }
    }

    private func wordScoreColor(_ score: Int) -> Color {
        switch score {
        case 85...: .green
        case 60..<85: .orange
        default: .red
        }
    }

    @ViewBuilder
    private func phonemeCell(_ op: PhonemeOp) -> some View {
        let (color, top, bottom): (Color, String, String?) = {
            switch op.kind {
            case .match: (.green, op.target ?? "", nil)
            case .substitute: (.orange, op.target ?? "", op.actual)
            case .delete: (.red, op.target ?? "", "×")
            case .insert: (.purple, "+", op.actual)
            }
        }()

        VStack(spacing: 2) {
            Text(top)
                .font(.title3.monospaced().bold())
            if let bottom {
                Text(bottom)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 40)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.5), lineWidth: 1))
    }

    private func legend(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(.secondary)
        }
    }

    private func issueCard(_ issue: DiagnosedIssue) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: issue.isKnownKoreanPattern
                      ? "person.crop.circle.badge.exclamationmark"
                      : "waveform.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(issue.title)
                    .font(.subheadline.bold())
                Spacer()
                if let word = issue.word {
                    Text(word)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                if issue.isKnownKoreanPattern {
                    Text("한국인 패턴")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            Text(issue.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .padding(.top, 2)
                Text(issue.howToFix)
                    .font(.footnote)
            }
            .padding(10)
            .background(.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))

            Button {
                onPlayReference()
            } label: {
                Label("원어민 발음 다시 듣기", systemImage: "speaker.wave.2")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary, lineWidth: 1))
    }
}
