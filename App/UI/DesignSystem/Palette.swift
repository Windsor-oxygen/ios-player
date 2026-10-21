import SwiftUI

extension DS {
    /// Семантические цвета. Системные цвета (`.primary`, `.secondary`, материалы)
    /// сами подстраиваются под светлую/тёмную тему и Reduce Transparency.
    enum Palette {
        /// Текст и контролы поверх фона «Сейчас играет» (фон всегда затемнён).
        static let onArtwork = Color.white
        static let onArtworkSecondary = Color.white.opacity(Opacity.secondary)
        static let onArtworkTertiary = Color.white.opacity(Opacity.tertiary)
        static let onArtworkTrack = Color.white.opacity(Opacity.track)
        static let shadow = Color.black
        static let scrim = Color.black
        static let warning = Color.orange
        static let destructive = Color.red
        static let success = Color.green
        static let playButtonBackground = Color.white
        static let playButtonForeground = Color.black
        /// Затемнение фона «Сейчас играет» сверху вниз — под ним читаются контролы.
        static let nowPlayingScrim: [Color] = [.black.opacity(0.12), .black.opacity(0.28), .black.opacity(0.62)]
        /// Целевая яркость цветов фона «Сейчас играет»: белый текст должен читаться.
        static let backgroundLuminance = 0.3
        /// Затемнение для недостающего третьего цвета сетки.
        static let meshShade = 0.55

        /// Пары цветов (сверху вниз) для сгенерированных обложек и фона треков без обложки.
        static let placeholderPairs: [(RGBColor, RGBColor)] = [
            (RGBColor(red: 0.98, green: 0.36, blue: 0.55), RGBColor(red: 0.45, green: 0.16, blue: 0.62)),
            (RGBColor(red: 0.35, green: 0.62, blue: 1.00), RGBColor(red: 0.16, green: 0.20, blue: 0.58)),
            (RGBColor(red: 0.30, green: 0.86, blue: 0.68), RGBColor(red: 0.05, green: 0.38, blue: 0.42)),
            (RGBColor(red: 1.00, green: 0.70, blue: 0.30), RGBColor(red: 0.82, green: 0.24, blue: 0.32)),
            (RGBColor(red: 0.66, green: 0.55, blue: 1.00), RGBColor(red: 0.27, green: 0.18, blue: 0.55)),
            (RGBColor(red: 0.20, green: 0.85, blue: 0.95), RGBColor(red: 0.48, green: 0.15, blue: 0.75)),
            (RGBColor(red: 0.95, green: 0.50, blue: 0.40), RGBColor(red: 0.35, green: 0.12, blue: 0.30)),
            (RGBColor(red: 0.55, green: 0.60, blue: 0.70), RGBColor(red: 0.18, green: 0.20, blue: 0.27)),
        ]

        /// Стабильная (не зависящая от запуска) пара цветов для строки.
        static func placeholderPair(for seed: String) -> (RGBColor, RGBColor) {
            // FNV-1a: `hashValue` в Swift меняется от запуска к запуску.
            var hash: UInt64 = 0xcbf2_9ce4_8422_2325
            for scalar in seed.unicodeScalars {
                hash ^= UInt64(scalar.value)
                hash = hash &* 0x0000_0100_0000_01B3
            }
            return placeholderPairs[Int(hash % UInt64(placeholderPairs.count))]
        }
    }
}

extension Color {
    init(_ rgb: RGBColor) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
