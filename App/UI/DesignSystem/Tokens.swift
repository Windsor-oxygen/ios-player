import SwiftUI

/// Дизайн-система «Аврора». Все числа оформления живут здесь;
/// во View используются только эти токены.
enum DS {
    /// Отступы: шкала с шагом 4 pt.
    enum Spacing {
        static let s: CGFloat = 8
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        /// Скругление иконки iOS — доля стороны (continuous-кривая).
        static let appIconRatio: CGFloat = 0.225
    }

    enum Size {
        /// Сторона превью в сетке выбора иконки (масштабируется Dynamic Type).
        static let iconPreview: CGFloat = 72
        /// Маленькое превью текущей иконки в строке настроек.
        static let iconPreviewInline: CGFloat = 28
    }

    enum Opacity {
        /// Тонкие разделители и обводки.
        static let hairline: Double = 0.3
    }

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let selection: CGFloat = 3
    }
}
