import SwiftUI

/// The shared record button: brand gradient at rest, red with a pulsing
/// level ring while recording.
struct MicButton: View {
    let isRecording: Bool
    let level: Float
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isRecording {
                    // Level-reactive halo
                    Circle()
                        .stroke(Color.red.opacity(0.25), lineWidth: 6)
                        .frame(width: size + 26, height: size + 26)
                        .scaleEffect(1.0 + CGFloat(min(level * 8, 0.5)))
                        .animation(.easeOut(duration: 0.12), value: level)
                }

                Circle()
                    .fill(isRecording
                          ? AnyShapeStyle(Color.red)
                          : AnyShapeStyle(Theme.heroGradient))
                    .frame(width: size, height: size)
                    .shadow(color: (isRecording ? Color.red : Theme.accent).opacity(0.35),
                            radius: 16, y: 8)
                    .scaleEffect(isRecording
                                 ? 1.0 + CGFloat(min(level * 5, 0.25))
                                 : 1.0)
                    .animation(.easeOut(duration: 0.12), value: level)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isRecording ? "녹음 중지" : "녹음 시작")
    }
}
