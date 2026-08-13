import SwiftUI

struct PracticeView: View {
    let word: String

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

                // Record button
                recordButton

                if isProcessing {
                    ProgressView("발음 분석 중…")
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                if let report {
                    DiagnosisResultView(report: report) {
                        appModel.tts.speak(word)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(word)
        .navigationBarTitleDisplayMode(.inline)
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
            let samples = appModel.recorder.stop()
            guard samples.count > 3_200 else {  // < 0.2 s
                errorMessage = "녹음이 너무 짧습니다. 다시 시도해 주세요."
                return
            }
            isProcessing = true
            defer { isProcessing = false }
            do {
                report = try await appModel.diagnose(word: word, samples: samples)
            } catch {
                errorMessage = error.localizedDescription
            }
        } else {
            report = nil
            guard await appModel.recorder.requestPermission() else {
                errorMessage = "마이크 권한이 필요합니다. 설정에서 허용해 주세요."
                return
            }
            do {
                try appModel.recorder.start()
            } catch {
                errorMessage = "녹음을 시작할 수 없습니다: \(error.localizedDescription)"
            }
        }
    }
}
