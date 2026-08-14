import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
            FreePracticeView()
                .navigationTitle("EngSoundly")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            ProgressDashboardView(progress: appModel.progress)
                        } label: {
                            Label("내 발음 리포트", systemImage: "chart.bar")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            WordCatalogView()
                        } label: {
                            Label("연습 단어장", systemImage: "book")
                        }
                    }
                }
        }
    }
}

/// The curated word list, now a secondary menu behind the 단어장 button.
struct WordCatalogView: View {
    @EnvironmentObject private var appModel: AppModel

    /// Per-category sound badge and hue — enough color to navigate by,
    /// not enough to shout.
    private static let styles: [String: (badge: String, color: Color)] = [
        "r-l": ("R·L", Color(red: 0.29, green: 0.39, blue: 0.93)),
        "f-p": ("F·P", .orange),
        "th": ("TH", .teal),
        "v-b": ("V·B", .pink),
        "z-j": ("Z", .purple),
        "sh-s": ("SH", .cyan),
        "ih-ee": ("ɪ·iː", .green),
        "ae-eh": ("æ·e", Color(red: 0.91, green: 0.36, blue: 0.36)),
        "cluster": ("STR", .brown),
        "er": ("ɚ", .mint),
    ]

    private func style(for id: String) -> (badge: String, color: Color) {
        Self.styles[id] ?? ("...", Theme.accent)
    }

    var body: some View {
        List {
            if appModel.isDemoMode {
                Section {
                    Label {
                        Text("데모 모드 — 음향 모델이 아직 설치되지 않아 예시 진단을 보여줍니다.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }

            ForEach(appModel.categories) { category in
                let style = style(for: category.id)
                Section {
                    ForEach(category.words) { entry in
                        NavigationLink {
                            PracticeView(word: entry.word,
                                         contrast: entry.contrast,
                                         contrastMeaning: entry.contrastMeaning)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.word)
                                        .font(.headline)
                                    Text(entry.meaning)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let contrast = entry.contrast {
                                    Text("vs \(contrast)")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(style.color)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(style.color.opacity(0.13), in: Capsule())
                                }
                            }
                        }
                    }
                } header: {
                    HStack(spacing: 10) {
                        Text(style.badge)
                            .font(.caption.weight(.bold).monospaced())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(style.color.gradient,
                                        in: RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(category.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(category.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .textCase(nil)
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("연습 단어장")
    }
}
