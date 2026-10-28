import SwiftUI

/// Ползунок позиции. Во время перетаскивания показывает положение пальца,
/// а не тики плеера, и отправляет seek только при отпускании.
/// Для VoiceOver подменяется стандартным Slider.
struct ScrubberView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragValue: TimeInterval?

    var body: some View {
        let clock = engine.clock
        let duration = max(clock.duration, 1)
        let shown = min(dragValue ?? clock.currentTime, duration)
        let isDragging = dragValue != nil

        VStack(spacing: DS.Spacing.s) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(DS.Palette.onArtworkTrack)
                    Capsule()
                        .fill(isDragging ? DS.Palette.onArtwork : DS.Palette.onArtwork.opacity(DS.Opacity.strong))
                        .frame(width: width * shown / duration)
                        .accentGlow(settings.accent.glows && isDragging, color: settings.accent.color)
                }
                .frame(height: isDragging ? DS.Size.scrubberActive : DS.Size.scrubberIdle)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragValue = min(max(value.location.x / width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let target = dragValue { engine.seek(to: target) }
                            dragValue = nil
                        }
                )
            }
            .frame(height: DS.Size.scrubberTouch)
            .animation(DS.Motion.animation(DS.Motion.scrub, reduceMotion: reduceMotion), value: isDragging)
            .sensoryFeedback(.selection, trigger: isDragging)

            HStack {
                Text(TimeFormatter.string(from: shown))
                Spacer()
                Text("−\(TimeFormatter.string(from: max(duration - shown, 0)))")
            }
            .font(DS.Font.time)
            .foregroundStyle(isDragging ? DS.Palette.onArtwork : DS.Palette.onArtworkSecondary)
        }
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { clock.currentTime }, set: { engine.seek(to: $0) }),
                in: 0...duration,
                step: ScrubberAccessibility.step(duration: duration)
            ) {
                Text("Позиция воспроизведения")
            }
            .accessibilityValue("\(TimeFormatter.string(from: clock.currentTime)) из \(TimeFormatter.string(from: duration))")
        }
    }
}

/// Параметры слайдера позиции для VoiceOver.
enum ScrubberAccessibility {
    /// Шаг не больше длины трека: иначе Slider падает (max stride must be positive)
    /// на треках короче шага. Слайдер строится всегда, даже без VoiceOver.
    static func step(duration: TimeInterval) -> Double {
        min(DS.Gesture.accessibilitySeekStep, duration)
    }
}

/// Тонкая полоса прогресса для мини-плеера.
struct MiniProgressBar: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppSettings.self) private var settings

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.tint.opacity(DS.Opacity.soft))
                Capsule()
                    .fill(.tint)
                    .frame(width: proxy.size.width * engine.clock.progress)
                    .accentGlow(settings.accent.glows, color: settings.accent.color)
            }
        }
        .frame(height: DS.Size.miniProgress)
        .accessibilityHidden(true)
    }
}
