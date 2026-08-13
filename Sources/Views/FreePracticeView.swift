import SwiftUI

/// The new main screen: speak any word or sentence, confirm what you meant,
/// then get pronunciation feedback.
struct FreePracticeView: View {
    @EnvironmentObject private var appModel: AppModel

    private enum Phase {
        case idle            // big mic, waiting
        case recording
        case processing      // recognizing intent + phonemes
        case review          // context box + suggestions, awaiting 교정
        case diagnosing
    }

    @State private var phase: Phase = .idle
    @State private var attempt: AppModel.FreeAttempt?
    @State private var editedText = ""
    @State private var report: DiagnosisReport?
    @State private var errorMessage: String?
    @FocusState private var textFocused: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let attempt {
                    contextBox(attempt)
                }

                if phase == .idle && attempt == nil {
                    Spacer(minLength: 60)
                    Text("궁금한 단어나 문장을 말해 보세요")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                micButton

                switch phase {
                case .recording:
                    Text("말이 끝나면 자동으로 인식돼요")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .processing:
                    ProgressView("무슨 말인지 알아듣는 중…")
                case .diagnosing:
                    ProgressView("발음 분석 중…")
                default:
                    EmptyView()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                if let report {
                    DiagnosisResultView(report: report,
                                        onPlayReference: { appModel.tts.speak(report.word) },
                                        onPlayUserAudio: { appModel.player.play(appModel.lastRecording) })
                }
            }
            .padding()
            .animation(.easeInOut(duration: 0.2), value: phase)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: - Context box (what you meant)

    @ViewBuilder
    private func contextBox(_ attempt: AppModel.FreeAttempt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("이렇게 말하려고 했나요?")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("말한 단어나 문장", text: $editedText, axis: .vertical)
                .font(.title2.weight(.semibold))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($textFocused)

            if !attempt.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(attempt.suggestions, id: \.self) { word in
                            Button {
                                editedText = word
                            } label: {
                                Text(word)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    Task { await runDiagnosis() }
                } label: {
                    Label("발음 교정", systemImage: "waveform.badge.magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(editedText.trimmingCharacters(in: .whitespaces).isEmpty
                          || phase == .diagnosing)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: - Mic

    private var micButton: some View {
        Button {
            Task { await toggleRecording() }
        } label: {
            ZStack {
                Circle()
                    .fill(phase == .recording ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)
                    .scaleEffect(phase == .recording
                                 ? 1.0 + CGFloat(min(appModel.recorder.level * 6, 0.35))
                                 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: appModel.recorder.level)
                Image(systemName: phase == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(phase == .processing || phase == .diagnosing)
        .accessibilityLabel(phase == .recording ? "녹음 중지" : "녹음 시작")
    }

    // MARK: - Flow

    private func toggleRecording() async {
        errorMessage = nil

        if phase == .recording {
            await finishRecording()
            return
        }

        report = nil
        attempt = nil
        editedText = ""
        guard await appModel.recorder.requestPermission() else {
            errorMessage = "마이크 권한이 필요합니다. 설정에서 허용해 주세요."
            return
        }
        _ = await SpeechIntentService.requestPermission()   // best effort; ASR degrades gracefully
        do {
            appModel.recorder.onAutoStop = {
                Task { await finishRecording() }
            }
            try appModel.recorder.start()
            phase = .recording
        } catch {
            errorMessage = "녹음을 시작할 수 없습니다: \(error.localizedDescription)"
            phase = .idle
        }
    }

    private func finishRecording() async {
        guard appModel.recorder.isRecording else { return }
        appModel.recorder.onAutoStop = nil
        let samples = appModel.recorder.stop()
        guard samples.count > 3_200 else {
            errorMessage = "녹음이 너무 짧습니다. 다시 시도해 주세요."
            phase = .idle
            return
        }

        phase = .processing
        do {
            let result = try await appModel.captureFreeAttempt(samples: samples)
            attempt = result
            editedText = result.intentText
            phase = .review
            if result.intentText.isEmpty && result.suggestions.isEmpty {
                errorMessage = "알아듣지 못했어요. 조금 더 크고 명확하게 말해 보세요."
            }
        } catch {
            errorMessage = error.localizedDescription
            phase = .idle
        }
    }

    private func runDiagnosis() async {
        guard let attempt else { return }
        textFocused = false
        errorMessage = nil
        phase = .diagnosing
        do {
            report = try appModel.diagnoseFree(text: editedText, attempt: attempt)
            phase = .review
        } catch {
            errorMessage = error.localizedDescription
            phase = .review
        }
    }
}
