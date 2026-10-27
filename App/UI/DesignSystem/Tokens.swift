import SwiftUI

/// Дизайн-система «Аврора». Все числа оформления живут здесь;
/// во View используются только эти токены (проверяет tools/check_design_tokens.py).
enum DS {
    /// Отступы: шкала с шагом 4 pt.
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Скругления (continuous-кривая).
    enum Radius {
        /// Миниатюры в строках списков.
        static let s: CGFloat = 6
        /// Мини-плеер (обложка), плейлисты, кнопки режимов.
        static let m: CGFloat = 8
        /// Карточки альбомов.
        static let l: CGFloat = 12
        /// Мини-плеер, шапка альбома, панели.
        static let xl: CGFloat = 16
        /// Обложка на экране «Сейчас играет».
        static let xxl: CGFloat = 22
        /// Скругление иконки iOS — доля стороны.
        static let appIconRatio: CGFloat = 0.225
        /// Круг: радиус — половина стороны.
        static let circleRatio: CGFloat = 0.5
    }

    enum Size {
        /// Минимальная зона нажатия (HIG).
        static let tapTarget: CGFloat = 44
        static let rowArtwork: CGFloat = 48
        static let miniArtwork: CGFloat = 44
        static let playlistArtwork: CGFloat = 56
        /// Минимальная ширина карточки альбома в сетке.
        static let albumCard: CGFloat = 150
        /// Карточка альбома в горизонтальной ленте исполнителя.
        static let albumCarousel: CGFloat = 144
        static let albumHeaderArtwork: CGFloat = 240
        /// Номер трека в альбоме.
        static let trackNumberWidth: CGFloat = 28
        static let playButton: CGFloat = 76
        static let transportButton: CGFloat = 52
        static let modeButton = CGSize(width: 36, height: 30)
        static let grabber = CGSize(width: 40, height: 5)
        static let scrubberIdle: CGFloat = 6
        static let scrubberActive: CGFloat = 10
        static let scrubberTouch: CGFloat = 28
        static let miniProgress: CGFloat = 2
        static let volumeSlider: CGFloat = 32
        static let iconPreview: CGFloat = 72
        static let iconPreviewInline: CGFloat = 28
        static let accentSwatch: CGFloat = 36
        static let emptyIllustration: CGFloat = 132
        /// Эквалайзер «сейчас играет» в строке.
        static let equalizer = CGSize(width: 18, height: 16)
    }

    enum Stroke {
        static let hairline: CGFloat = 0.5
        static let selection: CGFloat = 3
        /// Кольцо выбранного образца цвета — во сколько раз толще hairline.
        static let ringScale: CGFloat = 4
    }

    enum Opacity {
        /// Тонкие разделители и обводки.
        static let hairline: Double = 0.3
        /// Подложки-«стёкла» и пятна света.
        static let faint: Double = 0.12
        static let soft: Double = 0.22
        /// Неактивная дорожка прогресса на тёмном фоне.
        static let track: Double = 0.24
        static let tertiary: Double = 0.5
        static let secondary: Double = 0.72
        static let strong: Double = 0.88
        /// Недоступный трек.
        static let disabled: Double = 0.45
        /// Затемнение обложки под индикатором «сейчас играет».
        static let scrim: Double = 0.45
        /// Размытая обложка поверх цветного фона.
        static let backdrop: Double = 0.38
    }

    /// Масштаб обложки и кнопок.
    enum Scale {
        static let artworkPaused: CGFloat = 0.86
        static let pressed: CGFloat = 0.9
        /// Значок в сгенерированной обложке — доля стороны.
        static let placeholderSymbol: CGFloat = 0.4
        /// Внутренний круг иллюстрации пустого состояния: отступ — доля стороны.
        static let emptyInnerInset: CGFloat = 0.18
    }

    /// Смещения декоративных элементов.
    enum Offset {
        static let emptyNoteTrailing = CGSize(width: 50, height: -42)
        static let emptyNoteLeading = CGSize(width: -52, height: 36)
    }

    enum LineLimit {
        static let rowTitle = 1
        static let rowTitleLarge = 3
        static let headerTitle = 3
        static let nowPlayingTitle = 2
    }

    /// Экран обрезки своей обложки.
    enum Crop {
        static let maxZoom: CGFloat = 4
        /// Сетка третей.
        static let gridDivisions = 3
    }

    /// Пороги жестов.
    enum Gesture {
        static let dragMinimum: CGFloat = 16
        /// Свайп вниз, закрывающий плеер: пройденное и «предсказанное» расстояние.
        static let dismissDistance: CGFloat = 120
        static let dismissPredicted: CGFloat = 320
        /// Свайп вверх по мини-плееру, открывающий плеер.
        static let openDistance: CGFloat = 40
        /// Шаг слайдера позиции для VoiceOver, секунды.
        static let accessibilitySeekStep: Double = 5
    }
}
