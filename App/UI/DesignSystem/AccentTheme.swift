import SwiftUI
import UIKit

/// Акцентный цвет интерфейса (Настройки → «Оформление»). У каждого — светлая
/// и тёмная версия с контрастом не меньше 4.5:1 к фону темы (проверяет тест).
enum AccentTheme: String, CaseIterable, Identifiable, Sendable {
    case fuchsia
    case azure
    case mint
    case amber
    case violet
    case neon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuchsia: String(localized: "Фуксия")
        case .azure: String(localized: "Лазурь")
        case .mint: String(localized: "Мята")
        case .amber: String(localized: "Янтарь")
        case .violet: String(localized: "Фиалка")
        case .neon: String(localized: "Неон")
        }
    }

    /// sRGB 0xRRGGBB для светлой и тёмной темы.
    var hex: (light: UInt32, dark: UInt32) {
        switch self {
        case .fuchsia: (0xC8205E, 0xFF4D8D)
        case .azure: (0x0A6CD0, 0x5AB0FF)
        case .mint: (0x0A7656, 0x4BE3B0)
        case .amber: (0x995800, 0xFFB340)
        case .violet: (0x6B40D6, 0xA98BFF)
        case .neon: (0x00728C, 0x22E4FF)
        }
    }

    /// «Неон»: активные контролы мягко светятся.
    var glows: Bool { self == .neon }

    var uiColor: UIColor {
        let (light, dark) = hex
        return UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
