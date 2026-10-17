import SwiftUI

/// ⏮  −N  ⏯  +N  ⏭
struct TransportControls: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

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
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 72, height: 72)
                    .background(.white, in: Circle())
                    .foregroundStyle(.black)
            }
            .accessibilityLabel(engine.isPlaying ? "Пауза" : "Воспроизвести")
            Spacer()
            control("goforward.\(settings.skipInterval)", size: 24,
                    label: "Вперёд на \(settings.skipInterval) секунд") {
                engine.skip(by: TimeInterval(settings.skipInterval))
            }
            Spacer()
            control("forward.fill", size: 28, label: "Следующий трек") { engine.next() }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private func control(_ symbol: String, size: CGFloat, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}
