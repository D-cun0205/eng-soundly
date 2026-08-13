import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        NavigationStack {
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
            .navigationTitle("EngSoundly")
            .navigationDestination(for: String.self) { word in
                PracticeView(word: word)
            }
            .overlay {
                if !appModel.dictionaryReady {
                    ProgressView("발음 사전 로딩 중…")
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}
