import SwiftUI

/// Анимированный эквалайзер. Статичный на паузе и при Reduce Motion.
struct EqualizerBars: View {
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = isAnimating && !reduceMotion
        TimelineView(.animation(minimumInterval: DS.Motion.ambientFrameInterval, paused: !animate)) { context in
            let levels = DS.Equalizer.levels(at: animate ? context.date.timeIntervalSinceReferenceDate : nil)
            HStack(alignment: .bottom, spacing: DS.Spacing.xxs) {
                ForEach(levels.indices, id: \.self) { index in
                    Capsule()
                        .frame(height: DS.Size.equalizer.height * levels[index])
                }
            }
        }
        .frame(width: DS.Size.equalizer.width, height: DS.Size.equalizer.height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Индикатор «сейчас играет» в строке трека. Виден, только если это текущий
/// трек. Движок наблюдает только эта маленькая вью, а не вся строка списка.
struct NowPlayingIndicator: View {
    enum Placement {
        /// Поверх миниатюры обложки (с затемнением).
        case artwork
        /// Вместо номера трека.
        case inline
    }

    let trackID: UUID
    var placement = Placement.artwork

    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        if engine.currentTrack?.id == trackID {
            EqualizerBars(isAnimating: engine.isPlaying)
                .foregroundStyle(placement == .artwork ? DS.Palette.onArtwork : settings.accent.color)
                .accentGlow(settings.accent.glows, color: settings.accent.color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(placement == .artwork ? DS.Palette.scrim.opacity(DS.Opacity.scrim) : .clear)
                .transition(.opacity)
        }
    }
}

/// Для VoiceOver: строка текущего трека зачитывается со словами «сейчас играет».
private struct NowPlayingAccessibility: ViewModifier {
    let trackID: UUID
    @Environment(PlaybackEngine.self) private var engine

    func body(content: Content) -> some View {
        if engine.currentTrack?.id == trackID {
            content.accessibilityValue(engine.isPlaying ? Text("Сейчас играет") : Text("На паузе"))
        } else {
            content
        }
    }
}

extension View {
    func nowPlayingAccessibility(_ trackID: UUID) -> some View {
        modifier(NowPlayingAccessibility(trackID: trackID))
    }
}
