import Foundation

extension DS {
    /// Уровни полос эквалайзера (доли высоты 0…1).
    enum Equalizer {
        /// Статичная картинка: на паузе и при Reduce Motion.
        static let staticLevels: [CGFloat] = [0.45, 0.85, 0.6]
        private static let minimum: CGFloat = 0.25
        /// Сдвиг фаз соседних полос, доля периода.
        private static let phaseStep = 0.37

        /// `time == nil` — статичные уровни.
        static func levels(at time: TimeInterval?) -> [CGFloat] {
            guard let time else { return staticLevels }
            return staticLevels.indices.map { index in
                let cycle = time / Motion.equalizerPeriod + Double(index) * phaseStep
                let wave = (sin(cycle * .pi * 2) + 1) / 2
                return minimum + (1 - minimum) * CGFloat(wave)
            }
        }
    }
}
