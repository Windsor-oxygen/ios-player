import SwiftUI

/// Ползунок позиции. Во время перетаскивания показывает положение пальца,
/// а не тики плеера, и отправляет seek только при отпускании.
/// Для VoiceOver подменяется стандартным Slider.
struct ScrubberView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragValue: TimeInterval?

    var body: some View {
        let clock = engine.clock
        let duration = max(clock.duration, 1)
        let shown = min(dragValue ?? clock.currentTime, duration)
        let isDragging = dragValue != nil

        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white.opacity(isDragging ? 1 : 0.85))
                        .frame(width: width * shown / duration)
                }
                .frame(height: isDragging ? 10 : 6)
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
            .frame(height: 24)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: isDragging)
            .sensoryFeedback(.selection, trigger: isDragging)

            HStack {
                Text(TimeFormatter.string(from: shown))
                Spacer()
                Text("−\(TimeFormatter.string(from: max(duration - shown, 0)))")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.white.opacity(isDragging ? 0.95 : 0.65))
        }
        .accessibilityRepresentation {
            Slider(
                value: Binding(get: { clock.currentTime }, set: { engine.seek(to: $0) }),
                in: 0...duration,
                step: 5
            ) {
                Text("Позиция воспроизведения")
            }
            .accessibilityValue("\(TimeFormatter.string(from: clock.currentTime)) из \(TimeFormatter.string(from: duration))")
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
