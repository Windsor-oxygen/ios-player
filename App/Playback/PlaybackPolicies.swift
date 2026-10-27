import AVFoundation

/// Что делать, когда AVPlayerItem доиграл до конца.
enum TrackEndAction: Equatable {
    /// Не наш, уже обработанный или не текущий элемент.
    case ignore
    /// Следующий элемент был предзагружен — AVQueuePlayer переходит к нему сам,
    /// переход обрабатывает `syncCurrentItem`. Ничего не пересоздаём.
    case followPlayer
    /// Таймер сна «в конце трека»: остановиться на следующем треке.
    case stopAfterTrack
    /// Предзагрузки не было — перейти к следующему элементу очереди самим.
    case advance
}

/// Чистая логика окончания трека — покрыта unit-тестами.
///
/// Причина бага «двойного начала» в 1.1: конец трека обрабатывали два пути сразу —
/// автоматический переход AVQueuePlayer к предзагруженному элементу и `load()` из
/// уведомления об окончании. Здесь решение принимается по нашему состоянию
/// (была ли предзагрузка), а не по `player.currentItem` после асинхронного прыжка.
enum TrackEndPolicy {
    static func action(
        isKnownItem: Bool,
        isCurrentItem: Bool,
        alreadyHandled: Bool,
        hasPreloadedSuccessor: Bool,
        stopsAtEndOfTrack: Bool
    ) -> TrackEndAction {
        guard isKnownItem, !alreadyHandled else { return .ignore }
        if hasPreloadedSuccessor { return .followPlayer }
        guard isCurrentItem else { return .ignore }
        return stopsAtEndOfTrack ? .stopAfterTrack : .advance
    }
}

/// Когда перезапускать текущий трек перемоткой в 0, а не пересоздавать плеер.
enum RestartPolicy {
    /// Нажали на трек, который уже загружен (играет, на паузе или доиграл).
    static func restartsInPlace(tapped: UUID, current: UUID?, hasLoadedItem: Bool) -> Bool {
        hasLoadedItem && tapped == current
    }

    /// «Назад»: после порога — в начало трека; в первые секунды — к предыдущему,
    /// но если предыдущего нет (первый трек без повтора), это тот же трек — тоже в начало.
    static func previousRestartsCurrent(elapsed: TimeInterval, threshold: TimeInterval,
                                        previousEntry: UUID?, currentEntry: UUID?) -> Bool {
        elapsed > threshold || previousEntry == nil || previousEntry == currentEntry
    }
}

/// То, что нужно от плеера для перемотки (AVQueuePlayer; в тестах — мок).
@MainActor
protocol SeekablePlayer: AnyObject {
    func pause()
    func play()
    func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
              completionHandler: @escaping @Sendable (Bool) -> Void)
}

extension AVQueuePlayer: SeekablePlayer {}

/// Перемотка без звуковых артефактов: пауза → seek с нулевыми допусками → `play()`
/// строго в completion. Если пришла новая перемотка, старая звук не включает.
@MainActor
final class SeekSequencer {
    private(set) var isSeeking = false
    private var generation = 0
    private var shouldResume: (() -> Bool)?
    private var onFinish: (() -> Void)?
    private weak var player: SeekablePlayer?

    /// `shouldResume` спрашивается в момент окончания перемотки — если за это время
    /// поставили на паузу, звук не включится.
    func seek(_ player: SeekablePlayer, to seconds: TimeInterval,
              shouldResume: @escaping () -> Bool, onFinish: @escaping () -> Void) {
        generation += 1
        let current = generation
        self.player = player
        self.shouldResume = shouldResume
        self.onFinish = onFinish
        isSeeking = true
        player.pause()
        player.seek(
            to: CMTime(seconds: max(seconds, 0), preferredTimescale: Self.timescale),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish(current) }
        }
    }

    /// Сбросить незавершённую перемотку (плеер пересоздан, элемент заменён).
    func cancel() {
        generation += 1
        isSeeking = false
        shouldResume = nil
        onFinish = nil
    }

    private func finish(_ finished: Int) {
        guard finished == generation else { return }
        isSeeking = false
        if shouldResume?() == true { player?.play() }
        let done = onFinish
        shouldResume = nil
        onFinish = nil
        done?()
    }

    private static let timescale: CMTimeScale = 600
}
