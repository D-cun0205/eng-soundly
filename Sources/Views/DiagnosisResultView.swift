import SwiftUI

struct DiagnosisResultView: View {
    let report: DiagnosisReport
    let onPlayReference: () -> Void
    var onPlayUserAudio: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Score header
            HStack {
                VStack(alignment: .leading) {
                    Text("발음 점수")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(report.score)")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(scoreColor)
                    + Text(" / 100")
                        .font(.headline)
                        .foregroundStyle(.secondary)
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
        switch report.score {
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
