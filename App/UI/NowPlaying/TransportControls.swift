import SwiftUI

/// ⏮  −N  ⏯  +N  ⏭
struct TransportControls: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @State private var playTaps = 0
    @State private var skipTaps = 0

    var body: some View {
        HStack {
            control("backward.fill", size: 28, label: "Предыдущий трек") { engine.previous() }
            Spacer()
            control("gobackward.\(settings.skipInterval)", size: 24,
                    label: "Назад на \(settings.skipInterval) секунд") {
                engine.skip(by: -TimeInterval(settings.skipInterval))
            }
            Spacer()
            Button {
                playTaps += 1
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 76, height: 76)
                    .background(.white, in: Circle())
                    .foregroundStyle(.black)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(engine.isPlaying ? "Пауза" : "Воспроизвести")
            .sensoryFeedback(.impact(weight: .medium), trigger: playTaps)
            Spacer()
            control("goforward.\(settings.skipInterval)", size: 24,
                    label: "Вперёд на \(settings.skipInterval) секунд") {
                engine.skip(by: TimeInterval(settings.skipInterval))
            }
            Spacer()
            control("forward.fill", size: 28, label: "Следующий трек") { engine.next() }
        }
        .foregroundStyle(.white)
        .sensoryFeedback(.impact(weight: .light), trigger: skipTaps)
    }

    private func control(_ symbol: String, size: CGFloat, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button {
            skipTaps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}

/// Лёгкое «вдавливание» кнопки при нажатии (без анимации при Reduce Motion).
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
