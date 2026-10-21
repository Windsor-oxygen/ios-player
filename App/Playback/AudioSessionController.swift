import AVFoundation

/// AVAudioSession: категория `.playback`, прерывания, смена маршрута,
/// сброс медиасервисов. События отдаются движку через замыкания на main actor.
@MainActor
final class AudioSessionController {
    enum Interruption: Sendable {
        case began
        /// `shouldResume` — система разрешила продолжить (флаг `.shouldResume`).
        case ended(shouldResume: Bool)
    }

    var onInterruption: ((Interruption) -> Void)?
    /// Отключились наушники / Bluetooth — нужно поставить на паузу.
    var onOldDeviceUnavailable: (() -> Void)?
    var onMediaServicesReset: (() -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private let observers = NotificationTokens()

    init() {
        configure()
        let center = NotificationCenter.default
        observers.add(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = Self.parseInterruption(note) else { return }
            Task { @MainActor [weak self] in self?.onInterruption?(event) }
        })
        observers.add(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable else { return }
            Task { @MainActor [weak self] in self?.onOldDeviceUnavailable?() }
        })
        observers.add(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                // После сброса все объекты AVFoundation недействительны: настраиваем сессию заново.
                self?.configure()
                self?.onMediaServicesReset?()
            }
        })
    }

    /// Активировать при старте воспроизведения (не при запуске приложения,
    /// чтобы не прерывать чужую музыку, пока пользователь ничего не включил).
    @discardableResult
    func activate() -> Bool {
        do {
            try session.setActive(true)
            return true
        } catch {
            Log.playback.error("Не удалось активировать аудиосессию: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func configure() {
        do {
            try session.setCategory(.playback, mode: .default)
        } catch {
            Log.playback.error("Не удалось настроить аудиосессию: \(error.localizedDescription, privacy: .public)")
        }
    }

    private nonisolated static func parseInterruption(_ note: Notification) -> Interruption? {
        guard let info = note.userInfo,
              let rawType = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return nil }
        switch type {
        case .began:
            return .began
        case .ended:
            let rawOptions = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            return .ended(shouldResume: options.contains(.shouldResume))
        @unknown default:
            return nil
        }
    }
}
