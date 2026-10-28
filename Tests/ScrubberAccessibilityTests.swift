import SwiftUI
import XCTest
@testable import Player

/// Слайдер позиции для VoiceOver строится всегда. Если шаг больше длины трека,
/// SwiftUI завершает приложение (`max stride must be positive`) — так падал
/// экран «Сейчас играет» на треках короче 5 с.
@MainActor
final class ScrubberAccessibilityTests: XCTestCase {
    func testStepNeverExceedsDuration() {
        XCTAssertEqual(ScrubberAccessibility.step(duration: 1), 1)
        XCTAssertEqual(ScrubberAccessibility.step(duration: 2.5), 2.5)
        XCTAssertEqual(ScrubberAccessibility.step(duration: 240), DS.Gesture.accessibilitySeekStep)
    }

    /// Настоящий Slider с параметрами экрана: со старым шагом этот тест падал бы так же, как приложение.
    func testSliderBuildsForShortTracks() {
        for duration in [1, 2.5, 4.99, DS.Gesture.accessibilitySeekStep, 240] {
            // Падение — в инициализаторе Slider (проверка шага), body не нужен.
            _ = Slider(
                value: .constant(0),
                in: 0...duration,
                step: ScrubberAccessibility.step(duration: duration)
            ) {
                Text(verbatim: "")
            }
        }
    }
}
