import SwiftUI

/// Пустое состояние: иллюстрация, заголовок, подсказка и действия.
struct EmptyStateView<Actions: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    var message: LocalizedStringKey?
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            EmptyStateIllustration(symbol: symbol)
            VStack(spacing: DS.Spacing.s) {
                Text(title)
                    .font(DS.Font.title)
                if let message {
                    Text(message)
                        .font(DS.Font.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            actions
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.vertical, DS.Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(symbol: String, title: LocalizedStringKey, message: LocalizedStringKey? = nil) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}

/// Иллюстрация из фигур и SF Symbols в акцентном цвете.
struct EmptyStateIllustration: View {
    let symbol: String

    var body: some View {
        ZStack {
            Circle()
                .fill(.tint.opacity(DS.Opacity.faint))
            Circle()
                .fill(.tint.opacity(DS.Opacity.soft))
                .padding(DS.Size.emptyIllustration * DS.Scale.emptyInnerInset)
            Image(systemName: symbol)
                .font(DS.Font.illustration)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
            Image(systemName: "music.note")
                .font(DS.Font.illustrationAccent)
                .foregroundStyle(.tint.opacity(DS.Opacity.secondary))
                .offset(DS.Offset.emptyNoteTrailing)
            Image(systemName: "sparkle")
                .font(DS.Font.illustrationAccent)
                .foregroundStyle(.tint.opacity(DS.Opacity.tertiary))
                .offset(DS.Offset.emptyNoteLeading)
        }
        .frame(width: DS.Size.emptyIllustration, height: DS.Size.emptyIllustration)
        .accessibilityHidden(true)
    }
}

/// Лёгкое «вдавливание» кнопки при нажатии (без анимации при Reduce Motion).
struct PressScaleButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? DS.Scale.pressed : 1)
            .opacity(configuration.isPressed ? DS.Opacity.strong : 1)
            .animation(DS.Motion.animation(DS.Motion.press, reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
