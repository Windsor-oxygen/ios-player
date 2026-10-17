import SwiftUI

/// Ползунок позиции. Во время перетаскивания показывает значение пальца,
/// а не тики плеера, и отправляет seek только при отпускании.
struct ScrubberView: View {
    @Environment(PlaybackEngine.self) private var engine
    @State private var dragValue: TimeInterval?

    var body: some View {
        let clock = engine.clock
        let duration = max(clock.duration, 1)
        let shown = min(dragValue ?? clock.currentTime, duration)

        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { shown }, set: { dragValue = $0 }),
                in: 0...duration
            ) { editing in
                if !editing, let value = dragValue {
                    engine.seek(to: value)
                    dragValue = nil
                }
            }
            .tint(.white)
            .accessibilityLabel("Позиция воспроизведения")
            .accessibilityValue("\(TimeFormatter.string(from: shown)) из \(TimeFormatter.string(from: duration))")

            HStack {
                Text(TimeFormatter.string(from: shown))
                Spacer()
                Text("−\(TimeFormatter.string(from: max(duration - shown, 0)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityHidden(true)
        }
    }
}

/// Тонкая полоса прогресса для мини-плеера.
struct MiniProgressBar: View {
    @Environment(PlaybackEngine.self) private var engine

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * engine.clock.progress)
        }
        .frame(height: 2)
        .accessibilityHidden(true)
    }
}
