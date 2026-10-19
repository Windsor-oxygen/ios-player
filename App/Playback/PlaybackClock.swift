import Foundation
import Observation

/// Текущая позиция воспроизведения. Отдельный объект, чтобы частые
/// обновления (4 раза в секунду) перерисовывали только слайдер, а не весь экран.
@MainActor
@Observable
final class PlaybackClock {
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var progress: Double {
        duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    func set(time: TimeInterval) {
        let value = time.isFinite ? max(time, 0) : 0
        // Не дёргаем наблюдателей, если позиция почти не изменилась.
        if abs(value - currentTime) >= 0.05 { currentTime = value }
    }

    func set(duration: TimeInterval) {
        let value = duration.isFinite ? max(duration, 0) : 0
        if value != self.duration { self.duration = value }
    }
}
