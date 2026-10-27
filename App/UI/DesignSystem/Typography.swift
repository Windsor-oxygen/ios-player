import SwiftUI

extension DS {
    /// Шрифты. Только текстовые стили — всё масштабируется Dynamic Type.
    /// Заголовки — SF Pro Rounded, текст — SF Pro, время — моноширинные цифры.
    enum Font {
        static let title = SwiftUI.Font.system(.title2, design: .rounded, weight: .bold)
        static let subtitle = SwiftUI.Font.system(.title3, design: .rounded, weight: .medium)
        static let body = SwiftUI.Font.body
        static let bodyEmphasized = SwiftUI.Font.body.weight(.semibold)
        static let callout = SwiftUI.Font.callout
        static let subheadline = SwiftUI.Font.subheadline
        static let footnote = SwiftUI.Font.footnote
        static let caption = SwiftUI.Font.caption
        static let captionEmphasized = SwiftUI.Font.caption.weight(.semibold)
        static let miniTitle = SwiftUI.Font.subheadline.weight(.semibold)
        static let time = SwiftUI.Font.caption.monospacedDigit().weight(.medium)
        static let duration = SwiftUI.Font.footnote.monospacedDigit()
        static let trackNumber = SwiftUI.Font.body.monospacedDigit()
        static let banner = SwiftUI.Font.subheadline.weight(.semibold)

        /// Значки кнопок (SF Symbols) — тоже от текстовых стилей.
        static let playIcon = SwiftUI.Font.system(.largeTitle, weight: .bold)
        static let transportIcon = SwiftUI.Font.system(.title, weight: .semibold)
        static let skipIcon = SwiftUI.Font.system(.title2, weight: .semibold)
        static let controlIcon = SwiftUI.Font.system(.title3, weight: .semibold)
        static let modeIcon = SwiftUI.Font.system(.subheadline, weight: .semibold)
        static let smallIcon = SwiftUI.Font.caption
        static let badgeIcon = SwiftUI.Font.title3
        static let illustration = SwiftUI.Font.system(size: 52, weight: .semibold, design: .rounded)
        static let illustrationAccent = SwiftUI.Font.system(.title2, weight: .semibold)

        /// Значок в сгенерированной обложке: размер от стороны квадрата.
        static func placeholderSymbol(side: CGFloat) -> SwiftUI.Font {
            .system(size: side * Scale.placeholderSymbol, weight: .semibold)
        }
    }
}
