import SwiftUI

/// Per-phoneme accuracy overview: weakest sounds first, each leading to a
/// tailored drill.
struct ProgressDashboardView: View {
    @EnvironmentObject private var appModel: AppModel
    @ObservedObject private var progress: ProgressStore

    init(progress: ProgressStore) {
        self.progress = progress
    }

    var body: some View {
        List {
            let weak = progress.weakestPhonemes
            if weak.isEmpty {
                ContentUnavailableView(
                    "아직 데이터가 부족해요",
                    systemImage: "chart.bar",
                    description: Text("단어나 문장을 연습하면 취약한 소리를 찾아 맞춤 연습을 만들어 드려요. 음소마다 \(ProgressStore.minAttempts)번 이상 시도가 필요해요."))
            } else {
                Section {
                    ForEach(weak) { item in
                        NavigationLink(value: item.phoneme) {
                            phonemeRow(item)
                        }
                    }
                } header: {
                    Text("취약한 소리 — 탭하면 맞춤 연습")
                } footer: {
                    Text("신뢰도가 낮은 인식 결과는 집계에서 제외되어 있어요.")
                }

                Section {
                    Button("기록 초기화", role: .destructive) {
                        progress.reset()
                    }
                }
            }
        }
        .navigationTitle("내 발음 리포트")
        .navigationDestination(for: String.self) { phoneme in
            DrillSessionView(phoneme: phoneme)
        }
    }

    @ViewBuilder
    private func phonemeRow(_ item: ProgressStore.WeakPhoneme) -> some View {
        HStack(spacing: 12) {
            Text("/\(item.phoneme)/")
                .font(.title3.monospaced().bold())
                .frame(minWidth: 52)
            VStack(alignment: .leading, spacing: 4) {
                if let desc = PhonemeMapping.koreanDescription[item.phoneme] {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.quaternary)
                        Capsule()
                            .fill(accuracyColor(item.accuracy))
                            .frame(width: geo.size.width * item.accuracy)
                    }
                }
                .frame(height: 6)
            }
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int((item.accuracy * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(accuracyColor(item.accuracy))
                Text("\(item.attempts)회")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func accuracyColor(_ a: Double) -> Color {
        switch a {
        case 0.85...: .green
        case 0.6..<0.85: .orange
        default: .red
        }
    }
}

/// A guided run through drill words for one weak phoneme.
struct DrillSessionView: View {
    let phoneme: String

    @EnvironmentObject private var appModel: AppModel
    @State private var words: [String] = []
    @State private var index = 0
    @State private var doneCurrent = false

    var body: some View {
        VStack(spacing: 0) {
            if words.isEmpty {
                ContentUnavailableView("연습 단어를 찾지 못했어요",
                                       systemImage: "questionmark.circle")
            } else {
                // Progress header
                HStack {
                    Text("/\(phoneme)/ 집중 연습")
                        .font(.headline)
                    Spacer()
                    Text("\(index + 1) / \(words.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.top, 8)

                PracticeView(word: words[index]) { _ in
                    doneCurrent = true
                }
                .id(words[index])   // reset practice state per word

                if doneCurrent && index < words.count - 1 {
                    Button {
                        index += 1
                        doneCurrent = false
                    } label: {
                        Label("다음 단어", systemImage: "arrow.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                } else if doneCurrent {
                    Label("드릴 완료! 수고했어요", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .padding()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            words = appModel.candidates.drillWords(for: phoneme)
        }
    }
}
