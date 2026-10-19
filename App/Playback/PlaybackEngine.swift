import AVFoundation
import MediaPlayer
import Observation
import UIKit

/// Движок воспроизведения. UI только наблюдает за ним и вызывает команды.
///
/// `AVQueuePlayer` держит не больше двух элементов: текущий и предзагруженный
/// следующий (почти бесшовный переход). Вся логика порядка — в `PlaybackQueue`.
@MainActor
@Observable
final class PlaybackEngine {
    enum SleepTimer: Equatable {
        case off
        case at(Date)
        case endOfTrack
    }

    private(set) var queue = PlaybackQueue()
    private(set) var currentTrack: Track?
    /// Намерение «играть» (а не мгновенный статус плеера во время буферизации).
    private(set) var isPlaying = false
    private(set) var sleepTimer: SleepTimer = .off
    /// Короткое сообщение для пользователя (например, файл не воспроизводится).
    private(set) var message: String?

    let clock = PlaybackClock()

    @ObservationIgnored private var player = AVQueuePlayer()
    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let session = AudioSessionController()
    @ObservationIgnored private let nowPlaying = NowPlayingController()
    @ObservationIgnored private var remote: RemoteCommandController?
    @ObservationIgnored private let snapshots: PlaybackSnapshotStore
    @ObservationIgnored private let playerObservers = PlayerObservers()
    @ObservationIgnored private let notifications = NotificationTokens()

    /// AVPlayerItem → элемент очереди.
    @ObservationIgnored private var itemEntries: [ObjectIdentifier: UUID] = [:]
    @ObservationIgnored private var itemObservations: [ObjectIdentifier: NSKeyValueObservation] = [:]
    @ObservationIgnored private var currentItemID: ObjectIdentifier?
    @ObservationIgnored private var preloadedItemID: ObjectIdentifier?
    /// Позиция, на которую нужно перейти, когда элемент будет готов.
    @ObservationIgnored private var pendingSeek: (item: ObjectIdentifier, time: TimeInterval)?
    @ObservationIgnored private var isSeeking = false
    @ObservationIgnored private var seekGeneration = 0
    @ObservationIgnored private var publishedDuration: TimeInterval = 0
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var didRestore = false
    @ObservationIgnored private var lastPersistedAt = Date.distantPast
    @ObservationIgnored private var persistSequence = 0
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var messageTask: Task<Void, Never>?

    /// «Назад» в первые 3 секунды переключает трек, позже — перематывает в начало.
    static let restartThreshold: TimeInterval = 3
    private static let persistInterval: TimeInterval = 10

    init(library: LibraryStore, settings: AppSettings, locations: StorageLocations) {
        self.library = library
        self.settings = settings
        snapshots = PlaybackSnapshotStore(fileURL: locations.playbackState)
        player.actionAtItemEnd = .pause
        attachPlayerObservers()
        attachItemNotifications()

        session.onInterruption = { [weak self] event in self?.handleInterruption(event) }
        session.onOldDeviceUnavailable = { [weak self] in
            // Наушники или Bluetooth отключились — пауза, а не музыка из динамика.
            _ = self?.pause()
        }
        session.onMediaServicesReset = { [weak self] in self?.rebuildAfterMediaServicesReset() }
        setupRemoteCommands()
    }

    // MARK: - Restore

    /// Восстановить очередь и позицию с прошлого запуска. Звук не включается.
    func restore() async {
        guard !didRestore else { return }
        await library.ensureLoaded()
        defer { didRestore = true }
        guard var snapshot = await snapshots.load(),
              // Пользователь мог успеть включить музыку, пока грузилась библиотека.
              currentTrack == nil else { return }
        let known = Set(library.tracksByID.keys)
        snapshot.queue.removeTracks(Set(snapshot.queue.entries.map(\.trackID)).subtracting(known))
        guard !snapshot.queue.isEmpty else { return }
        queue = snapshot.queue
        load(queue.current, autoplay: false, at: snapshot.position)
    }

    // MARK: - Commands

    /// Пользователь нажал на конкретную песню в списке.
    /// Если её файла нет, не подменяем её молча соседней.
    func playTapped(_ trackIDs: [UUID], at index: Int) {
        if trackIDs.indices.contains(index),
           let tapped = library.tracksByID[trackIDs[index]], !tapped.isAvailable {
            show(String(localized: "Файл «\(tapped.title)» недоступен"))
            return
        }
        play(trackIDs, startAt: index)
    }

    /// Начать воспроизведение списка с позиции `index` (недоступные песни пропускаются).
    func play(_ trackIDs: [UUID], startAt index: Int = 0, shuffled: Bool = false) {
        guard !trackIDs.isEmpty else { return }
        let start = shuffled ? Int.random(in: 0..<trackIDs.count) : index
        queue.replace(with: trackIDs, startAt: start, shuffled: shuffled)
        load(queue.current, autoplay: true)
    }

    @discardableResult
    func play() -> MPRemoteCommandHandlerStatus {
        guard queue.current != nil else { return .noSuchContent }
        guard player.currentItem != nil else {
            load(queue.current, autoplay: true)
            return currentTrack == nil ? .noSuchContent : .success
        }
        guard session.activate() else {
            // Например, идёт звонок: система не отдаёт звук — не делаем вид, что играем.
            show(String(localized: "Сейчас нельзя включить звук. Попробуйте ещё раз."))
            return .commandFailed
        }
        resumeAfterInterruption = false
        player.play()
        isPlaying = true
        publishNowPlaying()
        persist(force: true)
        return .success
    }

    @discardableResult
    func pause() -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil else { return .noSuchContent }
        player.pause()
        isPlaying = false
        if !isSeeking { clock.set(time: currentSeconds) }
        publishNowPlaying()
        persist(force: true)
        return .success
    }

    @discardableResult
    func togglePlayPause() -> MPRemoteCommandHandlerStatus {
        isPlaying ? pause() : play()
    }

    @discardableResult
    func next() -> MPRemoteCommandHandlerStatus {
        guard !queue.isEmpty else { return .noSuchContent }
        let wasPlaying = isPlaying
        if let entry = queue.next() {
            load(entry, autoplay: wasPlaying)
        } else {
            // Конец очереди без повтора: к началу, на паузе.
            queue.rewindToStart()
            load(queue.current, autoplay: false)
        }
        return .success
    }

    @discardableResult
    func previous() -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil else { return .noSuchContent }
        if currentSeconds > Self.restartThreshold {
            return seek(to: 0)
        }
        load(queue.previous(), autoplay: isPlaying)
        return .success
    }

    @discardableResult
    func seek(to time: TimeInterval) -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil, let item = player.currentItem else { return .noSuchContent }
        let duration = clock.duration
        let target = duration > 0 ? min(max(time, 0), max(duration - 0.25, 0)) : max(time, 0)
        clock.set(time: target)
        if item.status != .readyToPlay {
            pendingSeek = (ObjectIdentifier(item), target)
        } else {
            isSeeking = true
            seekGeneration += 1
            let generation = seekGeneration
            player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.seekDidFinish(generation) }
            }
        }
        publishNowPlaying(elapsed: target)
        persist(force: true)
        return .success
    }

    /// Перемотка на ±N секунд (кнопки и экран блокировки).
    @discardableResult
    func skip(by delta: TimeInterval) -> MPRemoteCommandHandlerStatus {
        guard currentTrack != nil else { return .noSuchContent }
        return seek(to: (isSeeking ? clock.currentTime : currentSeconds) + delta)
    }

    func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        queueDidChange()
    }

    func cycleRepeatMode() {
        queue.repeatMode = queue.repeatMode.next
        queueDidChange()
    }

    func playNext(_ trackIDs: [UUID]) {
        let wasEmpty = currentTrack == nil
        queue.playNext(trackIDs)
        if wasEmpty {
            load(queue.current, autoplay: false)
        } else {
            queueDidChange()
        }
        show(String(localized: "Сыграет следующей"))
    }

    func addToQueue(_ trackIDs: [UUID]) {
        let wasEmpty = currentTrack == nil
        queue.append(trackIDs)
        if wasEmpty {
            load(queue.current, autoplay: false)
        } else {
            queueDidChange()
        }
        show(String(localized: "Добавлено в очередь"))
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        queue.moveUpcoming(fromOffsets: source, toOffset: destination)
        queueDidChange()
    }

    func removeUpcoming(atOffsets offsets: IndexSet) {
        queue.removeUpcoming(atOffsets: offsets)
        queueDidChange()
    }

    func jump(to entryID: UUID) {
        guard let entry = queue.jump(to: entryID) else { return }
        load(entry, autoplay: true)
    }

    /// Применить настройки кнопок экрана блокировки.
    func applyRemoteCommandSettings() {
        remote?.configure(mode: settings.lockScreenControls, skipInterval: settings.skipInterval)
    }

    /// Сохранить состояние немедленно (уход в фон).
    func saveState() {
        persist(force: true)
    }

    // MARK: - Library changes

    /// Треки удалены из библиотеки или обновились их метаданные.
    func libraryDidChange(removed: Set<UUID>) {
        if !removed.isEmpty {
            let removedCurrent = queue.removeTracks(removed)
            if queue.isEmpty {
                stopAndClear()
                return
            }
            if removedCurrent {
                load(queue.current, autoplay: isPlaying)
                return
            }
            queueDidChange()
        }
        guard let track = currentTrack, let updated = library.tracksByID[track.id], updated != track else { return }
        currentTrack = updated
        if updated.artworkKey != track.artworkKey { loadArtwork(for: updated) }
        publishNowPlaying()
    }

    // MARK: - Sleep timer

    func startSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        player.volume = 1
        let wasEndOfTrack = sleepTimer == .endOfTrack
        let duration = TimeInterval(minutes * 60)
        sleepTimer = .at(Date.now.addingTimeInterval(duration))
        if wasEndOfTrack { preloadNext() }
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            await self?.fadeOutAndStop()
        }
    }

    func startSleepTimerAtEndOfTrack() {
        sleepTask?.cancel()
        sleepTask = nil
        player.volume = 1
        sleepTimer = .endOfTrack
        // Следующий трек не предзагружаем — плеер остановится в конце текущего.
        preloadNext()
    }

    func cancelSleepTimer() {
        sleepTask?.cancel()
        sleepTask = nil
        player.volume = 1
        let wasEndOfTrack = sleepTimer == .endOfTrack
        sleepTimer = .off
        if wasEndOfTrack { preloadNext() }
    }

    private func fadeOutAndStop() async {
        let steps = 20
        for step in 1...steps {
            guard !Task.isCancelled else {
                player.volume = 1
                return
            }
            player.volume = Float(steps - step) / Float(steps)
            try? await Task.sleep(for: .milliseconds(400))
        }
        pause()
        player.volume = 1
        sleepTimer = .off
        sleepTask = nil
    }

    // MARK: - Loading

    private var currentSeconds: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    /// Первый воспроизводимый элемент, начиная с `entry` (пропуская удалённые и битые файлы).
    private func firstPlayable(from entry: QueueEntry?) -> QueueEntry? {
        var candidate = entry
        var attempts = 0
        while let current = candidate, attempts <= queue.entries.count {
            if let track = library.tracksByID[current.trackID], track.isAvailable {
                return current
            }
            attempts += 1
            candidate = queue.next()
        }
        return nil
    }

    private func load(_ entry: QueueEntry?, autoplay: Bool, at position: TimeInterval = 0) {
        guard let entry = firstPlayable(from: entry), let track = library.tracksByID[entry.trackID] else {
            if !queue.isEmpty { show(String(localized: "Нет доступных для воспроизведения песен")) }
            stopAndClear()
            return
        }
        resetPlayerItems()
        let item = makeItem(for: track, entryID: entry.id)
        player.insert(item, after: nil)
        currentItemID = ObjectIdentifier(item)
        if position > 0 { pendingSeek = (ObjectIdentifier(item), position) }

        currentTrack = track
        clock.set(duration: track.duration)
        clock.set(time: position)
        loadArtwork(for: track)
        preloadNext()

        if autoplay {
            play()
        } else {
            player.pause()
            isPlaying = false
            publishNowPlaying(elapsed: position)
            persist(force: true)
        }
    }

    private func makeItem(for track: Track, entryID: UUID) -> AVPlayerItem {
        let item = AVPlayerItem(url: library.fileURL(for: track))
        let id = ObjectIdentifier(item)
        itemEntries[id] = entryID
        itemObservations[id] = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            let status = observed.status
            Task { @MainActor [weak self] in self?.itemStatusChanged(id, status: status) }
        }
        return item
    }

    private func forget(_ id: ObjectIdentifier) {
        itemEntries.removeValue(forKey: id)
        itemObservations.removeValue(forKey: id)?.invalidate()
        if pendingSeek?.item == id { pendingSeek = nil }
    }

    private func resetPlayerItems() {
        player.removeAllItems()
        for observation in itemObservations.values { observation.invalidate() }
        itemObservations.removeAll()
        itemEntries.removeAll()
        currentItemID = nil
        preloadedItemID = nil
        pendingSeek = nil
        isSeeking = false
    }

    /// Предзагрузить то, что сыграет после текущего трека (с учётом repeat и таймера сна).
    private func preloadNext() {
        if let preloadedItemID {
            if let item = player.items().first(where: { ObjectIdentifier($0) == preloadedItemID }) {
                player.remove(item)
            }
            forget(preloadedItemID)
            self.preloadedItemID = nil
        }
        guard sleepTimer != .endOfTrack,
              let currentItem = player.currentItem,
              let next = queue.entryAfterCompletion,
              let track = library.tracksByID[next.trackID],
              track.isAvailable else {
            player.actionAtItemEnd = .pause
            return
        }
        let item = makeItem(for: track, entryID: next.id)
        guard player.canInsert(item, after: currentItem) else {
            forget(ObjectIdentifier(item))
            player.actionAtItemEnd = .pause
            return
        }
        player.actionAtItemEnd = .advance
        player.insert(item, after: currentItem)
        preloadedItemID = ObjectIdentifier(item)
    }

    private func queueDidChange() {
        preloadNext()
        publishNowPlaying()
        persist(force: true)
    }

    private func stopAndClear() {
        player.pause()
        resetPlayerItems()
        artworkTask?.cancel()
        isPlaying = false
        currentTrack = nil
        queue.clear()
        clock.set(time: 0)
        clock.set(duration: 0)
        nowPlaying.clear()
        persist(force: true)
    }

    private func loadArtwork(for track: Track) {
        artworkTask?.cancel()
        guard let key = track.artworkKey else { return }
        let store = library.artwork
        let trackID = track.id
        artworkTask = Task { [weak self] in
            guard let image = await store.image(key: key, size: .large),
                  !Task.isCancelled,
                  let self,
                  self.currentTrack?.id == trackID else { return }
            self.nowPlaying.setArtwork(image, for: trackID)
        }
    }

    // MARK: - Player events

    private func attachPlayerObservers() {
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            let seconds = time.seconds
            Task { @MainActor [weak self] in self?.tick(seconds) }
        }
        let currentItem = player.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncCurrentItem() }
        }
        let status = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.syncTimeControlStatus() }
        }
        playerObservers.attach(to: player, timeToken: token, observations: [currentItem, status])
    }

    private func attachItemNotifications() {
        let center = NotificationCenter.default
        notifications.add(center.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            Task { @MainActor [weak self] in self?.itemDidFinish(id) }
        })
        notifications.add(center.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            let id = ObjectIdentifier(item)
            Task { @MainActor [weak self] in self?.itemDidFail(id) }
        })
    }

    private func tick(_ seconds: TimeInterval) {
        guard !isSeeking, pendingSeek == nil, currentTrack != nil else { return }
        clock.set(time: seconds)
        if let item = player.currentItem, item.status == .readyToPlay {
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0 {
                clock.set(duration: duration)
                // Реальная длительность могла отличаться от метаданных — обновляем экран блокировки.
                if abs(duration - publishedDuration) > 1 { publishNowPlaying() }
            }
        }
        if isPlaying { persist() }
    }

    private func seekDidFinish(_ generation: Int) {
        guard generation == seekGeneration else { return }
        isSeeking = false
        publishNowPlaying()
    }

    private func itemStatusChanged(_ id: ObjectIdentifier, status: AVPlayerItem.Status) {
        switch status {
        case .readyToPlay:
            guard id == currentItemID, let pending = pendingSeek, pending.item == id else { return }
            pendingSeek = nil
            seek(to: pending.time)
        case .failed:
            itemDidFail(id)
        default:
            break
        }
    }

    /// Плеер сам перешёл к другому элементу (обычно — к предзагруженному следующему).
    private func syncCurrentItem() {
        let newID = player.currentItem.map(ObjectIdentifier.init)
        guard newID != currentItemID else { return }
        guard let newID else {
            // Элементы закончились без нашей команды — очередь доиграна.
            if let oldID = currentItemID { forget(oldID) }
            currentItemID = nil
            finishQueue()
            return
        }
        guard newID == preloadedItemID, let entryID = itemEntries[newID] else { return }
        if let oldID = currentItemID { forget(oldID) }
        currentItemID = newID
        preloadedItemID = nil
        _ = queue.advanceAfterCompletion()
        if queue.current?.id != entryID { queue.jump(to: entryID) }
        if let track = queue.current.flatMap({ library.tracksByID[$0.trackID] }) {
            currentTrack = track
            clock.set(duration: track.duration)
            clock.set(time: 0)
            loadArtwork(for: track)
        }
        preloadNext()
        publishNowPlaying(elapsed: 0)
        persist(force: true)
    }

    private func syncTimeControlStatus() {
        switch player.timeControlStatus {
        case .paused where isPlaying && !isSeeking:
            // Остановлено не нами: конец трека, система, отключение наушников.
            isPlaying = false
            clock.set(time: currentSeconds)
            publishNowPlaying()
            persist(force: true)
        case .playing where !isPlaying:
            isPlaying = true
            publishNowPlaying()
        default:
            break
        }
    }

    private func itemDidFinish(_ id: ObjectIdentifier) {
        // Если плеер уже перешёл к предзагруженному — это обработает syncCurrentItem.
        guard id == currentItemID, player.currentItem.map(ObjectIdentifier.init) == id else {
            syncCurrentItem()
            return
        }
        if sleepTimer == .endOfTrack {
            cancelSleepTimer()
            if let next = queue.advanceAfterCompletion() {
                load(next, autoplay: false)
            } else {
                finishQueue()
            }
            return
        }
        if let next = queue.advanceAfterCompletion() {
            load(next, autoplay: true)
        } else {
            finishQueue()
        }
    }

    private func itemDidFail(_ id: ObjectIdentifier) {
        guard let entryID = itemEntries[id] else { return }
        if let trackID = queue.entries.first(where: { $0.id == entryID })?.trackID,
           let track = library.tracksByID[trackID] {
            // Удалённый файл пометит пересканирование; «битым» считаем только существующий.
            let path = library.fileURL(for: track).path(percentEncoded: false)
            if FileManager.default.fileExists(atPath: path) {
                library.markUnplayable(trackID)
            }
        }
        if id == preloadedItemID {
            if let item = player.items().first(where: { ObjectIdentifier($0) == id }) { player.remove(item) }
            forget(id)
            preloadedItemID = nil
            player.actionAtItemEnd = .pause
            return
        }
        guard id == currentItemID else {
            forget(id)
            return
        }
        let title = currentTrack?.title ?? ""
        show(String(localized: "Не удалось воспроизвести «\(title)»"))
        let wasPlaying = isPlaying
        if let next = queue.next() {
            load(next, autoplay: wasPlaying)
        } else {
            finishQueue()
        }
        // Файл мог быть удалён через «Файлы» — пересканируем библиотеку.
        Task { await library.refresh() }
    }

    /// Очередь доиграна: к первому треку, на паузе.
    private func finishQueue() {
        queue.rewindToStart()
        load(queue.current, autoplay: false)
    }

    // MARK: - Audio session events

    private func handleInterruption(_ event: AudioSessionController.Interruption) {
        switch event {
        case .began:
            // Звонок, Siri, будильник: система уже остановила звук.
            if isPlaying { resumeAfterInterruption = true }
            player.pause()
            isPlaying = false
            clock.set(time: currentSeconds)
            publishNowPlaying()
            persist(force: true)
        case .ended(let shouldResume):
            let resume = shouldResume && resumeAfterInterruption
            resumeAfterInterruption = false
            if resume { play() }
        }
    }

    private func rebuildAfterMediaServicesReset() {
        Log.playback.notice("Сброс медиасервисов — пересоздаём плеер")
        let position = clock.currentTime
        playerObservers.detach()
        resetPlayerItems()
        player = AVQueuePlayer()
        player.actionAtItemEnd = .pause
        attachPlayerObservers()
        remote?.invalidate()
        setupRemoteCommands()
        isPlaying = false
        if queue.current != nil {
            load(queue.current, autoplay: false, at: position)
        }
    }

    // MARK: - Remote commands & Now Playing

    private func setupRemoteCommands() {
        let handlers = RemoteCommandController.Handlers(
            play: { [weak self] in self?.play() ?? .commandFailed },
            pause: { [weak self] in self?.pause() ?? .commandFailed },
            togglePlayPause: { [weak self] in self?.togglePlayPause() ?? .commandFailed },
            next: { [weak self] in self?.next() ?? .commandFailed },
            previous: { [weak self] in self?.previous() ?? .commandFailed },
            skipForward: { [weak self] in
                guard let self else { return .commandFailed }
                return self.skip(by: TimeInterval(self.settings.skipInterval))
            },
            skipBackward: { [weak self] in
                guard let self else { return .commandFailed }
                return self.skip(by: -TimeInterval(self.settings.skipInterval))
            },
            seek: { [weak self] time in self?.seek(to: time) ?? .commandFailed }
        )
        remote = RemoteCommandController(handlers: handlers)
        applyRemoteCommandSettings()
    }

    private func publishNowPlaying(elapsed: TimeInterval? = nil) {
        guard let track = currentTrack else {
            nowPlaying.clear()
            return
        }
        let duration = clock.duration > 0 ? clock.duration : track.duration
        publishedDuration = duration
        let position = elapsed ?? (isSeeking || pendingSeek != nil ? clock.currentTime : currentSeconds)
        nowPlaying.update(.init(
            track: track,
            elapsed: position,
            duration: duration,
            isPlaying: isPlaying,
            queueIndex: queue.currentIndex,
            queueCount: queue.entries.count
        ))
    }

    private func show(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    // MARK: - Persistence

    private func persist(force: Bool = false) {
        // До восстановления не перезаписываем сохранённое пустым состоянием.
        guard didRestore else { return }
        let now = Date.now
        guard force || now.timeIntervalSince(lastPersistedAt) >= Self.persistInterval else { return }
        lastPersistedAt = now
        persistSequence += 1
        let snapshot = PlaybackSnapshot(
            queue: queue,
            position: pendingSeek?.time ?? (isSeeking ? clock.currentTime : currentSeconds)
        )
        let sequence = persistSequence
        let store = snapshots
        Task { await store.save(snapshot, sequence: sequence) }
    }
}

/// Периодический наблюдатель времени и KVO плеера.
/// Снимаются при `detach()` или освобождении.
private final class PlayerObservers {
    private weak var player: AVPlayer?
    private var timeToken: Any?
    private var observations: [NSKeyValueObservation] = []

    func attach(to player: AVPlayer, timeToken: Any, observations: [NSKeyValueObservation]) {
        detach()
        self.player = player
        self.timeToken = timeToken
        self.observations = observations
    }

    func detach() {
        if let timeToken, let player {
            player.removeTimeObserver(timeToken)
        }
        timeToken = nil
        for observation in observations { observation.invalidate() }
        observations.removeAll()
        player = nil
    }

    deinit {
        detach()
    }
}
