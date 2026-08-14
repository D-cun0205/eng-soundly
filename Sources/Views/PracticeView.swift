import SwiftUI

struct PracticeView: View {
    let word: String
    /// Minimal-pair partner (rice ↔ lice) and its Korean gloss, if any.
    var contrast: String? = nil
    var contrastMeaning: String? = nil
    /// Called after each successful diagnosis (used by drill sessions).
    var onDiagnosed: ((DiagnosisReport) -> Void)? = nil

    @EnvironmentObject private var appModel: AppModel
    @State private var report: DiagnosisReport?
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var targetIPA: [String] {
        appModel.dictionary.primary(for: word) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Word card
                VStack(spacing: 8) {
                    Text(word)
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    if !targetIPA.isEmpty {
                        Text("/" + targetIPA.joined() + "/")
                            .font(.title3.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 16) {
                        Button {
                            appModel.tts.speak(word)
                        } label: {
                            Label("원어민 발음", systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(.bordered)

                        Button {
                            appModel.tts.speakSlowly(word)
                        } label: {
                            Label("천천히", systemImage: "tortoise.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))

                if let contrast {
                    minimalPairCard(contrast)
                }

                // Record button
                recordButton

                if appModel.recorder.isRecording {
                    Text("말이 끝나면 자동으로 분석돼요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isProcessing {
                    ProgressView("발음 분석 중…")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let report {
                    DiagnosisResultView(report: report,
                                        onPlayReference: { appModel.tts.speak(word) },
                                        onPlayUserAudio: { appModel.player.play(appModel.lastRecording) })
                }
            }
            .padding()
        }
        .navigationTitle(word)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Why the "vs" word exists: one sound apart, completely different
    /// meaning. Side-by-side listening makes the stakes concrete.
    @ViewBuilder
    private func minimalPairCard(_ contrast: String) -> some View {
        let contrastIPA = appModel.dictionary.primary(for: contrast) ?? []

        VStack(alignment: .leading, spacing: 10) {
            Label("한 소리 차이", systemImage: "arrow.left.arrow.right")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(spacing: 0) {
                pairColumn(word: word, ipa: targetIPA, meaning: nil)
                Text("↔")
                    .font(.title3)
                    .foregroundStyle(.tertiary)
                    .frame(width: 32)
                pairColumn(word: contrast, ipa: contrastIPA, meaning: contrastMeaning)
            }

            Text("이 발음을 놓치면 '\(word)'가 '\(contrast)\(contrastMeaning.map { " (\($0))" } ?? "")'로 들려요. 번갈아 들으며 차이를 잡아보세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.blue.opacity(0.15), lineWidth: 1))
    }

    @ViewBuilder
    private func pairColumn(word: String, ipa: [String], meaning: String?) -> some View {
        VStack(spacing: 4) {
            Text(word)
                .font(.headline)
            if !ipa.isEmpty {
                Text("/" + ipa.joined() + "/")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if let meaning {
                Text(meaning)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button {
                appModel.tts.speak(word)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity)
    }

    private var recordButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            ZStack {
                Circle()
                    .fill(appModel.recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 88, height: 88)
                    .scaleEffect(appModel.recorder.isRecording
                                 ? 1.0 + CGFloat(min(appModel.recorder.level * 6, 0.35))
                                 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: appModel.recorder.level)
                Image(systemName: appModel.recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .accessibilityLabel(appModel.recorder.isRecording ? "녹음 중지" : "녹음 시작")
    }

    private func toggleRecording() async {
        errorMessage = nil

        if appModel.recorder.isRecording {
            await finishRecording()
        } else {
            report = nil
            guard await appModel.recorder.requestPermission() else {
                errorMessage = "마이크 권한이 필요합니다. 설정에서 허용해 주세요."
                return
            }
            do {
                appModel.recorder.maxSeconds = 4.8   // single word: one model window
                appModel.recorder.onAutoStop = {
                    Task { await finishRecording() }
                }
                try appModel.recorder.start()
            } catch {
                errorMessage = "녹음을 시작할 수 없습니다: \(error.localizedDescription)"
            }
        }
    }

    private func finishRecording() async {
        guard appModel.recorder.isRecording else { return }
        appModel.recorder.onAutoStop = nil
        let samples = appModel.recorder.stop()
        guard samples.count > 3_200 else {  // < 0.2 s
            errorMessage = "녹음이 너무 짧습니다. 다시 시도해 주세요."
            return
        }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let result = try await appModel.diagnose(word: word, samples: samples)
            report = result
            onDiagnosed?(result)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
