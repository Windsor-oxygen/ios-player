import SwiftUI

extension DS {
    /// «Дышащий» MeshGradient 3×3 фона «Сейчас играет».
    enum Mesh {
        static let width = 3
        static let height = 3
        /// Сколько цветов обложки нужно сетке.
        static let paletteSize = 3
        /// Амплитуда смещения внутренних точек, доля стороны.
        private static let amplitude: Float = 0.09

        /// Расстановка трёх цветов обложки по 9 узлам сетки.
        static func colors(_ palette: [Color]) -> [Color] {
            let c0 = palette.first ?? .black
            let c1 = palette.dropFirst().first ?? c0
            let c2 = palette.dropFirst(2).first ?? c1
            return [c0, c0, c1,
                    c2, c1, c0,
                    c1, c2, c2]
        }

        /// Узлы сетки. `time == nil` — неподвижная сетка (пауза, Reduce Motion).
        /// Углы закреплены, середины рёбер скользят вдоль них, центр «плавает».
        static func points(at time: TimeInterval?) -> [SIMD2<Float>] {
            let phase = Float((time ?? 0) / Motion.meshPeriod * .pi * 2)
            let wobble: Float = time == nil ? 0 : amplitude
            func shift(_ offset: Float) -> Float {
                0.5 + sin(phase + offset) * wobble
            }
            let top = SIMD2<Float>(shift(0), 0)
            let left = SIMD2<Float>(0, shift(1.3))
            let center = SIMD2<Float>(shift(2.1), shift(0.7))
            let right = SIMD2<Float>(1, shift(2.9))
            let bottom = SIMD2<Float>(shift(3.7), 1)
            return [
                SIMD2<Float>(0, 0), top, SIMD2<Float>(1, 0),
                left, center, right,
                SIMD2<Float>(0, 1), bottom, SIMD2<Float>(1, 1),
            ]
        }
    }
}
