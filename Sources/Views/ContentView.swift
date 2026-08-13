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
                            WordCatalogView()
                        } label: {
                            Label("연습 단어장", systemImage: "book")
                        }
                    }
                }
                .navigationDestination(for: String.self) { word in
                    PracticeView(word: word)
                }
        }
    }
}

/// The curated word list, now a secondary menu behind the 단어장 button.
struct WordCatalogView: View {
    @EnvironmentObject private var appModel: AppModel

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
                Section {
                    ForEach(category.words) { entry in
                        NavigationLink(value: entry.word) {
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
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.quaternary, in: Capsule())
                                }
                            }
                        }
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.title)
                        Text(category.subtitle)
                            .font(.caption2)
                            .textCase(nil)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("연습 단어장")
    }
}
