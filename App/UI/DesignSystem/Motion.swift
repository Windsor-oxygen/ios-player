import SwiftUI

extension DS {
    /// Анимации «Авроры»: мягкие пружины. При Reduce Motion — без анимации.
    enum Motion {
        static let standard = Animation.spring(response: 0.4, dampingFraction: 0.85)
        /// Обложка «дышит» на play/pause.
        static let artwork = Animation.spring(response: 0.5, dampingFraction: 0.72)
        static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let scrub = Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let trackChange = Animation.easeInOut(duration: 0.35)
        /// Смена фона между треками.
        static let background = Animation.easeInOut(duration: 0.8)
        /// Период «дыхания» градиента фона, секунды.
        static let meshPeriod: Double = 14
        /// Период эквалайзера в строке, секунды.
        static let equalizerPeriod: Double = 0.9
        /// Кадров в секунду для медленных фоновых анимаций (экономия батареи).
        static let ambientFrameInterval: Double = 1.0 / 30

        static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : animation
        }
    }
}
