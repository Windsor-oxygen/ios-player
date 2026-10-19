import SwiftUI

/// ⏮  −N  ⏯  +N  ⏭
struct TransportControls: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @State private var playTaps = 0
    @State private var skipTaps = 0

    var body: some View {
        HStack {
            control("backward.fill", font: DS.Font.transportIcon, label: "Предыдущий трек") { engine.previous() }
            Spacer()
            control("gobackward.\(settings.skipInterval)", font: DS.Font.skipIcon,
                    label: "Назад на \(settings.skipInterval) секунд") {
                engine.skip(by: -TimeInterval(settings.skipInterval))
            }
            Spacer()
            Button {
                playTaps += 1
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(DS.Font.playIcon)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(DS.Palette.playButtonForeground)
                    .frame(width: DS.Size.playButton, height: DS.Size.playButton)
                    .background(DS.Palette.playButtonBackground, in: Circle())
                    .dsShadow(DS.Shadow.control)
                    .accentGlow(settings.accent.glows, color: settings.accent.color)
            }
            .buttonStyle(PressScaleButtonStyle())
            .accessibilityLabel(engine.isPlaying ? "Пауза" : "Воспроизвести")
            .sensoryFeedback(.impact(weight: .medium), trigger: playTaps)
            Spacer()
            control("goforward.\(settings.skipInterval)", font: DS.Font.skipIcon,
                    label: "Вперёд на \(settings.skipInterval) секунд") {
                engine.skip(by: TimeInterval(settings.skipInterval))
            }
            Spacer()
            control("forward.fill", font: DS.Font.transportIcon, label: "Следующий трек") { engine.next() }
        }
        .foregroundStyle(DS.Palette.onArtwork)
        .sensoryFeedback(.impact(weight: .light), trigger: skipTaps)
    }

    private func control(_ symbol: String, font: Font, label: LocalizedStringKey,
                         action: @escaping () -> Void) -> some View {
        Button {
            skipTaps += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(font)
                .frame(width: DS.Size.transportButton, height: DS.Size.transportButton)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(label)
    }
}
