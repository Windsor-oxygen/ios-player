import SwiftUI

/// Всплывающее сообщение («Сыграет следующей», ошибки воспроизведения).
struct MessageBanner: View {
    let message: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let message {
                Text(message)
                    .font(DS.Font.banner)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DS.Spacing.l)
                    .padding(.vertical, DS.Spacing.s)
                    .background(.regularMaterial, in: Capsule())
                    .dsShadow(DS.Shadow.miniPlayer)
                    .padding(.top, DS.Spacing.s)
                    .padding(.horizontal, DS.Spacing.l)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion), value: message)
        .allowsHitTesting(false)
    }
}
