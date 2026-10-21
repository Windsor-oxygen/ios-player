import XCTest
@testable import Player

/// Акцентные цвета читаются на фоне своей темы (WCAG ≥ 4.5:1),
/// заглушки обложек стабильны между запусками.
final class DesignSystemTests: XCTestCase {
    private let lightBackgrounds: [UInt32] = [0xFFFFFF, 0xF2F2F7]
    private let darkBackgrounds: [UInt32] = [0x000000, 0x1C1C1E]

    func testAccentContrast() {
        for theme in AccentTheme.allCases {
            for background in lightBackgrounds {
                XCTAssertGreaterThanOrEqual(contrast(theme.hex.light, background), 4.5, "\(theme) светлая")
            }
            for background in darkBackgrounds {
                XCTAssertGreaterThanOrEqual(contrast(theme.hex.dark, background), 4.5, "\(theme) тёмная")
            }
            XCTAssertFalse(theme.title.isEmpty)
        }
        XCTAssertEqual(AccentTheme.allCases.filter(\.glows), [.neon])
    }

    func testPlaceholderColorsAreStable() {
        let first = DS.Palette.placeholderPair(for: "Северное сияние")
        let second = DS.Palette.placeholderPair(for: "Северное сияние")
        XCTAssertEqual(first.0, second.0)
        XCTAssertEqual(first.1, second.1)
        // Разные названия распределяются по разным цветам.
        let titles = (0..<64).map { "Песня \($0)" }
        let distinct = Set(titles.map { DS.Palette.placeholderPair(for: $0).0 })
        XCTAssertGreaterThan(distinct.count, DS.Palette.placeholderPairs.count / 2)
    }

    func testEqualizerLevelsStayInRange() {
        XCTAssertEqual(DS.Equalizer.levels(at: nil), DS.Equalizer.staticLevels)
        for step in 0..<100 {
            for level in DS.Equalizer.levels(at: Double(step) * 0.037) {
                XCTAssertGreaterThan(level, 0)
                XCTAssertLessThanOrEqual(level, 1)
            }
        }
    }

    private func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }

    private func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((hex >> shift) & 0xFF) / 255
            return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }
}
