import AVKit
import MediaPlayer
import SwiftUI

/// Системный слайдер громкости: синхронизирован с аппаратными кнопками.
/// В симуляторе не отображается — это ограничение iOS, не ошибка.
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .white
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Выбор устройства вывода: AirPods, Bluetooth-колонка, AirPlay.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.prioritizesVideoDevices = false
        view.tintColor = UIColor(DS.Palette.onArtworkSecondary)
        view.activeTintColor = UIColor(DS.Palette.onArtwork)
        view.accessibilityLabel = String(localized: "Устройство вывода звука")
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
