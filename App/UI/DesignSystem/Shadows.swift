import SwiftUI

/// Тень: прозрачность цвета, радиус размытия и смещение вниз.
struct ShadowToken {
    let opacity: Double
    let radius: CGFloat
    let y: CGFloat
}

extension DS {
    enum Shadow {
        static let card = ShadowToken(opacity: 0.22, radius: 10, y: 5)
        static let header = ShadowToken(opacity: 0.35, radius: 18, y: 10)
        static let miniPlayer = ShadowToken(opacity: 0.18, radius: 16, y: 6)
        static let control = ShadowToken(opacity: 0.25, radius: 12, y: 6)
        static let artworkPlaying = ShadowToken(opacity: 0.55, radius: 36, y: 22)
        static let artworkPaused = ShadowToken(opacity: 0.32, radius: 16, y: 8)
        /// Неоновое свечение акцентного цвета «Неон».
        static let glow = ShadowToken(opacity: 0.85, radius: 10, y: 0)
    }
}

extension View {
    func dsShadow(_ token: ShadowToken, color: Color = DS.Palette.shadow) -> some View {
        shadow(color: color.opacity(token.opacity), radius: token.radius, y: token.y)
    }

    /// Свечение акцентом — только для акцента «Неон».
    func accentGlow(_ isOn: Bool, color: Color = .accentColor) -> some View {
        shadow(color: color.opacity(isOn ? DS.Shadow.glow.opacity : 0), radius: isOn ? DS.Shadow.glow.radius : 0)
    }
}
