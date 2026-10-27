import Foundation
import Observation
import UIKit

/// Состояние библиотеки для UI. Вся тяжёлая работа (скан, метаданные,
/// обложки, копирование, JSON) выполняется вне main thread.
@MainActor
@Observable
final class LibraryStore {
    private(set) var tracks: [Track] = []
    private(set) var tracksByID: [UUID: Track] = [:]
    private(set) var albums: [Album] = []
    private(set) var artists: [Artist] = []
    private(set) var playlists: [Playlist] = []
    /// Растёт при каждом изменении треков — ключ для пересчёта списков в `.task(id:)`.
    private(set) var revision = 0
    private(set) var isLoaded = false
    private(set) var isRefreshing = false
    /// Индекс не удалось прочитать или сохранить в копию: в этой сессии ничего
    /// не записываем (ни библиотеку, ни состояние воспроизведения), чтобы не затереть данные.
    @ObservationIgnored private(set) var isReadOnly = false
    /// Итог последнего импорта для алерта; UI обнуляет после показа.
    var lastReport: ImportReport?
    /// Разовое сообщение (например, о восстановлении повреждённого индекса).
    var notice: String?

    /// Вызывается после каждого изменения треков; `removed` — исчезнувшие из библиотеки ID.
    @ObservationIgnored var onTracksChanged: ((_ removed: Set<UUID>) -> Void)?

    @ObservationIgnored private let locations: StorageLocations
    @ObservationIgnored private let persistence: LibraryPersistence
    @ObservationIgnored private let importer: FileImporter
    @ObservationIgnored let artwork: ArtworkStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshPending = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var albumsByID: [String: Album] = [:]
    @ObservationIgnored private var artistsByID: [String: Artist] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let artworkReader: ArtworkReader
    /// Ключ миниатюр → трек, из которого их можно пересоздать.
    @ObservationIgnored private var artworkOwners: [String: UUID] = [:]
    @ObservationIgnored private var artworkRepairs: [String: Task<String?, Never>] = [:]
    /// Ключи, которые в этой сессии восстановить не удалось — не пытаемся снова на каждом показе.
    @ObservationIgnored private var unrecoverableArtwork = Set<String>()
    @ObservationIgnored private var artworkRecoveryTask: Task<Void, Never>?

    /// Разовое восстановление обложек, потерянных в 1.0/1.1 (новый ключ UserDefaults).
    private static let artworkRecoveryKey = "library.artworkRecovery"
    private static let artworkRecoveryVersion = 1
    /// Фоновое восстановление — не больше двух файлов одновременно, чтобы не мешать интерфейсу.
    private static let artworkRecoveryConcurrency = 2

    /// Параллельных чтений метаданных: больше — без выигрыша на A13 и с риском подтормаживаний.
    private static let metadataConcurrency = 4
    /// Сколько результатов копить перед обновлением UI.
    private static let metadataBatch = 25

    init(locations: StorageLocations, defaults: UserDefaults = .standard, artworkReader: ArtworkReader = .tags) {
        self.locations = locations
        self.defaults = defaults
        self.artworkReader = artworkReader
        self.persistence = LibraryPersistence(fileURL: locations.libraryIndex)
        self.importer = FileImporter(locations: locations)
        self.artwork = ArtworkStore(directory: locations.artwork)
    }

    // MARK: - Lookup

    func album(id: String) -> Album? { albumsByID[id] }
    func artist(id: String) -> Artist? { artistsByID[id] }
    func playlist(id: UUID) -> Playlist? { playlists.first { $0.id == id } }

    func tracks(ids: [UUID]) -> [Track] {
        ids.compactMap { tracksByID[$0] }
    }

    func fileURL(for track: Track) -> URL {
        locations.fileURL(forRelativePath: track.relativePath)
    }

    /// AVPlayer не смог воспроизвести файл — помечаем, чтобы пропускать его в очереди.
    func markUnplayable(_ id: UUID) {
        guard let index = tracks.firstIndex(where: { $0.id == id }), !tracks[index].isUnplayable else { return }
        var updated = tracks
        updated[index].isUnplayable = true
        setTracks(updated)
        scheduleSave()
    }

    // MARK: - Loading & refresh

    func ensureLoaded() async {
        if loadTask == nil {
            loadTask = Task { await self.loadIndex() }
        }
        await loadTask?.value
    }

    private func loadIndex() async {
        await Self.migrateArtwork(locations)
        switch await persistence.load() {
        case .loaded(let index):
            playlists = index.playlists
            setTracks(index.tracks)
        case .empty:
            break
        case .recovered(let index, let backupCreated):
            playlists = index.playlists
            setTracks(index.tracks)
            isReadOnly = !backupCreated
            if backupCreated {
                notice = String(localized: "Файл библиотеки был повреждён. Его копия сохранена, библиотека восстановлена, плейлистов спасено: \(index.playlists.count). Музыкальные файлы не пострадали.")
            } else {
                notice = String(localized: "Файл библиотеки повреждён, а сделать его копию не удалось. Чтобы ничего не потерять, изменения в этот раз не сохраняются. Освободите место на iPhone и перезапустите приложение.")
            }
        case .unreadable:
            isReadOnly = true
            notice = String(localized: "Не удалось прочитать файл библиотеки. Чтобы ничего не потерять, изменения в этот раз не сохраняются. Перезапустите приложение.")
        }
        isLoaded = true
    }

    /// Пересканировать папку. Повторные вызовы во время работы объединяются.
    func refresh() async {
        if let running = refreshTask {
            refreshPending = true
            await running.value
            return
        }
        let task = Task {
            repeat {
                refreshPending = false
                await performRefresh()
            } while refreshPending
            refreshTask = nil
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        await ensureLoaded()
        isRefreshing = true
        defer { isRefreshing = false }

        let inboxReport = await importer.drainInbox()
        let scanned = await Self.scan(locations)
        let result = LibraryReconciler.reconcile(existing: tracks, scanned: scanned)
        Log.library.info("Скан: найдено \(scanned.count), новых \(result.addedCount), отсутствует \(result.missingCount)")
        if result.tracks != tracks {
            setTracks(result.tracks)
            scheduleSave()
        }
        await loadPendingMetadata()
        startArtworkRecoveryIfNeeded()
        if !inboxReport.importedPaths.isEmpty || !inboxReport.failures.isEmpty {
            present(inboxReport)
        }
    }

    private nonisolated static func migrateArtwork(_ locations: StorageLocations) async {
        ArtworkStore.migrate(from: locations.legacyArtwork, to: locations.artwork)
    }

    private nonisolated static func scan(_ locations: StorageLocations) async -> [ScannedFile] {
        FolderScanner.scan(locations)
    }

    /// Что делать с обложкой трека после чтения тегов.
    private enum ArtworkUpdate: Sendable {
        /// Файл не прочитался или миниатюру не удалось записать — прежнюю обложку не трогаем.
        case keep
        case set(String)
        /// Файл прочитан, обложки в нём нет.
        case clear
    }

    private struct ProcessedMetadata: Sendable {
        let id: UUID
        let metadata: TrackMetadata
        let artwork: ArtworkUpdate
    }

    private nonisolated static func process(id: UUID, url: URL, artwork: ArtworkStore) async -> ProcessedMetadata {
        var metadata = await MetadataLoader.load(url: url)
        let update: ArtworkUpdate
        if !metadata.isPlayable {
            update = .keep
        } else if let data = metadata.artworkData {
            update = artwork.store(imageData: data).map(ArtworkUpdate.set) ?? .keep
        } else {
            update = .clear
        }
        metadata.artworkData = nil
        return ProcessedMetadata(id: id, metadata: metadata, artwork: update)
    }

    private func loadPendingMetadata() async {
        let pending = tracks
            .filter { $0.needsMetadata && !$0.isMissing }
            .map { (id: $0.id, url: locations.fileURL(forRelativePath: $0.relativePath)) }
        guard !pending.isEmpty else { return }
        let artwork = self.artwork

        await withTaskGroup(of: ProcessedMetadata.self) { group in
            var next = 0
            func enqueue() {
                guard next < pending.count else { return }
                let item = pending[next]
                next += 1
                group.addTask { await Self.process(id: item.id, url: item.url, artwork: artwork) }
            }
            for _ in 0..<Self.metadataConcurrency { enqueue() }

            var buffer: [ProcessedMetadata] = []
            while let result = await group.next() {
                buffer.append(result)
                enqueue()
                if buffer.count >= Self.metadataBatch {
                    apply(buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
            }
            apply(buffer)
        }
        scheduleSave()
    }

    private func apply(_ results: [ProcessedMetadata]) {
        guard !results.isEmpty else { return }
        var updated = tracks
        var positions: [UUID: Int] = [:]
        for (index, track) in updated.enumerated() { positions[track.id] = index }
        for result in results {
            // Трек мог быть удалён, пока читались теги.
            guard let index = positions[result.id] else { continue }
            var track = updated[index]
            let meta = result.metadata
            track.needsMetadata = false
            track.isUnplayable = !meta.isPlayable
            // Файл не прочитался (в т. ч. временно): прежние теги и обложку не затираем.
            if meta.isPlayable {
                track.title = meta.title ?? Track.defaultTitle(forRelativePath: track.relativePath)
                track.artist = meta.artist
                track.album = meta.album
                track.trackNumber = meta.trackNumber
                track.discNumber = meta.discNumber
                track.duration = meta.duration
            }
            switch result.artwork {
            case .keep: break
            case .set(let key): track.artworkKey = key
            case .clear: track.artworkKey = nil
            }
            updated[index] = track
        }
        setTracks(updated)
    }

    // MARK: - Import

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        await ensureLoaded()
        // Индикатор на время копирования; refresh() снимет его по завершении.
        isRefreshing = true
        let report = await importer.importFiles(urls)
        await refresh()
        present(report)
    }

    /// Возвращает имя сохранённого файла.
    func importDownloaded(_ staged: URL, fileName: String) async -> Result<String, ImportError> {
        await ensureLoaded()
        do {
            let path = try await importer.importDownloaded(staged, fileName: fileName)
            await refresh()
            return .success((path as NSString).lastPathComponent)
        } catch let error as ImportError {
            try? FileManager.default.removeItem(at: staged)
            return .failure(error)
        } catch {
            try? FileManager.default.removeItem(at: staged)
            return .failure(.copyFailed(error.localizedDescription))
        }
    }

    /// Показать итог импорта; если предыдущий ещё не показан — объединить.
    func present(_ report: ImportReport) {
        if var existing = lastReport {
            existing.importedPaths += report.importedPaths
            existing.failures += report.failures
            existing.setAsideCount += report.setAsideCount
            lastReport = existing
        } else {
            lastReport = report
        }
    }

    // MARK: - Deletion

    /// Удаляет файлы с диска и записи из библиотеки и плейлистов.
    /// Только по явной команде пользователя с подтверждением.
    func delete(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        let deleted = tracks.filter { ids.contains($0.id) }
        // Аудиофайлы — по явной команде пользователя; вместе с ними наши файлы своих обложек.
        let urls = deleted.map { locations.fileURL(forRelativePath: $0.relativePath) }
            + deleted.compactMap(\.customArtworkPath).map { locations.supportURL(forRelativePath: $0) }
        await Self.removeFiles(urls)
        forget(ids)
        let keys = Set(tracks.flatMap { [$0.artworkKey, $0.customArtworkKey].compactMap { $0 } })
        let artwork = self.artwork
        Task.detached(priority: .utility) { artwork.removeUnreferenced(keeping: keys) }
    }

    /// Убирает записи из библиотеки и плейлистов, не трогая диск
    /// (для песен, файлов которых уже нет).
    func forget(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        // Свои обложки убранных записей — наши файлы, без трека они не нужны.
        let customPaths = tracks.filter { ids.contains($0.id) }.compactMap(\.customArtworkPath)
        if !customPaths.isEmpty {
            let locations = self.locations
            Task.detached(priority: .utility) { await Self.removeCustomArtwork(customPaths, locations: locations) }
        }
        setTracks(tracks.filter { !ids.contains($0.id) })
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { ids.contains($0) }
        }
        scheduleSave()
    }

    private nonisolated static func removeFiles(_ urls: [URL]) async {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Playlists

    @discardableResult
    func createPlaylist(named name: String, trackIDs: [UUID] = []) -> Playlist {
        let playlist = Playlist(name: Self.cleanName(name), trackIDs: trackIDs)
        playlists.append(playlist)
        scheduleSave()
        return playlist
    }

    func renamePlaylist(_ id: UUID, to name: String) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].name = Self.cleanName(name)
        scheduleSave()
    }

    func deletePlaylist(_ id: UUID) {
        playlists.removeAll { $0.id == id }
        scheduleSave()
    }

    func addTracks(_ ids: [UUID], toPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].trackIDs.append(contentsOf: ids)
        scheduleSave()
    }

    func removeTracks(at offsets: IndexSet, fromPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].trackIDs.remove(atOffsets: offsets)
        scheduleSave()
    }

    func moveTracks(from source: IndexSet, to destination: Int, inPlaylist id: UUID) {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[index].trackIDs.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    private static func cleanName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? String(localized: "Новый плейлист") : trimmed
    }

    // MARK: - Persistence

    /// Сохранить немедленно (уход в фон).
    func saveNow() async {
        saveTask?.cancel()
        saveTask = nil
        do {
            try await persistence.save(snapshot)
        } catch {
            Log.library.error("Не удалось сохранить библиотеку: \(error.localizedDescription, privacy: .public)")
        }
    }

    private var snapshot: LibraryIndex {
        LibraryIndex(tracks: tracks, playlists: playlists)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = self.snapshot
        let persistence = self.persistence
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            do {
                try await persistence.save(snapshot)
            } catch {
                Log.library.error("Не удалось сохранить библиотеку: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Artwork

    /// Своя обложка для треков (одного или всего альбома). `jpeg` — уже обрезанная
    /// квадратная картинка. Каждому треку — свой файл `CustomArtwork/<id>.jpg`,
    /// миниатюры общие (ключ по содержимому). В аудиофайлы ничего не пишется.
    func setCustomArtwork(_ jpeg: Data, for ids: [UUID]) async throws {
        guard !isReadOnly else { throw CustomArtworkError.readOnlyLibrary }
        let targets = ids.filter { tracksByID[$0] != nil }
        guard !targets.isEmpty else { return }
        let key = try await Self.saveCustomArtwork(jpeg, for: targets, locations: locations, artwork: artwork)
        var updated = tracks
        for index in updated.indices where targets.contains(updated[index].id) {
            updated[index].customArtworkKey = key
            updated[index].customArtworkPath = StorageLocations.customArtworkPath(for: updated[index].id)
        }
        unrecoverableArtwork.remove(key)
        setTracks(updated)
        scheduleSave()
    }

    /// Вернуть обложку из файла (или заглушку). Удаляется только наш файл своей обложки.
    func resetCustomArtwork(for ids: [UUID]) async {
        let targets = Set(ids)
        let paths = tracks.filter { targets.contains($0.id) }.compactMap(\.customArtworkPath)
        guard !paths.isEmpty else { return }
        var updated = tracks
        for index in updated.indices where targets.contains(updated[index].id) {
            updated[index].customArtworkKey = nil
            updated[index].customArtworkPath = nil
        }
        setTracks(updated)
        scheduleSave()
        await Self.removeCustomArtwork(paths, locations: locations)
    }

    private nonisolated static func saveCustomArtwork(
        _ jpeg: Data, for ids: [UUID], locations: StorageLocations, artwork: ArtworkStore
    ) async throws -> String {
        // Сначала миниатюры: если на них не хватит места, файлы своей обложки не пишем.
        guard let key = artwork.store(imageData: jpeg) else { throw CustomArtworkError.saveFailed }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: locations.customArtwork, withIntermediateDirectories: true)
            for id in ids {
                try jpeg.write(to: locations.supportURL(forRelativePath: StorageLocations.customArtworkPath(for: id)),
                               options: [.atomic])
            }
        } catch {
            Log.library.error("Не удалось сохранить свою обложку: \(error.localizedDescription, privacy: .public)")
            throw CustomArtworkError.saveFailed
        }
        return key
    }

    private nonisolated static func removeCustomArtwork(_ paths: [String], locations: StorageLocations) async {
        for path in paths {
            try? FileManager.default.removeItem(at: locations.supportURL(forRelativePath: path))
        }
    }

    /// Миниатюра обложки. Если её нет на диске (очищено системой, потеряно в старой
    /// версии) — пересоздаётся из своей обложки или из тегов файла, вне main thread.
    func artworkImage(key: String, size: ArtworkStore.Size) async -> UIImage? {
        if let image = await artwork.image(key: key, size: size) { return image }
        guard await restoreArtwork(key: key) else { return nil }
        return await artwork.image(key: key, size: size)
    }

    /// `true` — миниатюры с этим ключом снова на диске.
    func restoreArtwork(key: String) async -> Bool {
        if let running = artworkRepairs[key] { return await running.value == key }
        guard !unrecoverableArtwork.contains(key),
              let id = artworkOwners[key], let track = tracksByID[id] else { return false }
        let source = artworkSource(for: track, key: key)
        let artwork = self.artwork
        let reader = artworkReader
        let task = Task { await Self.rebuildArtwork(from: source, artwork: artwork, reader: reader) }
        artworkRepairs[key] = task
        let rebuilt = await task.value
        artworkRepairs[key] = nil
        if rebuilt == key { return true }
        unrecoverableArtwork.insert(key)
        // Картинку в тегах заменили — переключаем трек на новую.
        if let rebuilt, case .tags = source { replaceArtworkKey(key, with: rebuilt) }
        return false
    }

    private enum ArtworkSource: Sendable {
        case custom(URL)
        case tags(URL)
    }

    private func artworkSource(for track: Track, key: String) -> ArtworkSource {
        if key == track.customArtworkKey, let path = track.customArtworkPath {
            return .custom(locations.supportURL(forRelativePath: path))
        }
        return .tags(fileURL(for: track))
    }

    private nonisolated static func rebuildArtwork(
        from source: ArtworkSource, artwork: ArtworkStore, reader: ArtworkReader
    ) async -> String? {
        switch source {
        case .custom(let url):
            guard let data = try? Data(contentsOf: url) else { return nil }
            return artwork.store(imageData: data)
        case .tags(let url):
            guard case .found(let data) = await reader.read(url) else { return nil }
            return artwork.store(imageData: data)
        }
    }

    private func replaceArtworkKey(_ old: String, with new: String) {
        var updated = tracks
        for index in updated.indices where updated[index].artworkKey == old {
            updated[index].artworkKey = new
        }
        setTracks(updated)
        scheduleSave()
    }

    /// Один раз после обновления до 1.1.1: вернуть обложки, потерянные в 1.0/1.1
    /// (кэш очищен системой или ключ затёрт). В фоне, свои обложки не трогаем.
    private func startArtworkRecoveryIfNeeded() {
        guard artworkRecoveryTask == nil, !isReadOnly,
              defaults.integer(forKey: Self.artworkRecoveryKey) < Self.artworkRecoveryVersion else { return }
        artworkRecoveryTask = Task(priority: .utility) { await self.recoverLostArtwork() }
    }

    /// Для тестов: дождаться окончания разового восстановления.
    func waitForArtworkRecovery() async {
        await artworkRecoveryTask?.value
    }

    private func recoverLostArtwork() async {
        let candidates = tracks
            .filter { !$0.isMissing && !$0.needsMetadata && $0.customArtworkKey == nil }
            .map { (id: $0.id, url: fileURL(for: $0), key: $0.artworkKey) }
        let artwork = self.artwork
        let reader = artworkReader
        await withTaskGroup(of: (UUID, String)?.self) { group in
            var next = 0
            func enqueue() {
                guard next < candidates.count else { return }
                let item = candidates[next]
                next += 1
                group.addTask(priority: .utility) {
                    await Self.recoverArtwork(url: item.url, key: item.key, artwork: artwork, reader: reader)
                        .map { (item.id, $0) }
                }
            }
            for _ in 0..<Self.artworkRecoveryConcurrency { enqueue() }

            var found: [UUID: String] = [:]
            while let result = await group.next() {
                if let pair = result { found[pair.0] = pair.1 }
                enqueue()
                if found.count >= Self.metadataBatch {
                    applyRecoveredArtwork(found)
                    found.removeAll()
                }
            }
            applyRecoveredArtwork(found)
        }
        defaults.set(Self.artworkRecoveryVersion, forKey: Self.artworkRecoveryKey)
        Log.library.info("Восстановление обложек после обновления завершено")
    }

    /// Новый ключ, если обложку удалось вернуть; `nil` — менять нечего.
    private nonisolated static func recoverArtwork(
        url: URL, key: String?, artwork: ArtworkStore, reader: ArtworkReader
    ) async -> String? {
        if let key, artwork.hasImages(key: key) { return nil }
        guard case .found(let data) = await reader.read(url),
              let recovered = artwork.store(imageData: data) else { return nil }
        return recovered == key ? nil : recovered
    }

    private func applyRecoveredArtwork(_ found: [UUID: String]) {
        guard !found.isEmpty else { return }
        var updated = tracks
        for index in updated.indices {
            // Пока шло восстановление, пользователь мог поставить свою обложку.
            guard let key = found[updated[index].id], updated[index].customArtworkKey == nil else { continue }
            updated[index].artworkKey = key
        }
        setTracks(updated)
        scheduleSave()
    }

    // MARK: - Derived state

    private func setTracks(_ newTracks: [Track]) {
        let removed = Set(tracksByID.keys).subtracting(newTracks.map(\.id))
        tracks = newTracks
        tracksByID = Dictionary(newTracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let visible = newTracks.filter { !$0.isMissing }
        albums = LibraryQuery.albums(from: visible)
        artists = LibraryQuery.artists(from: visible)
        albumsByID = Dictionary(albums.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        artistsByID = Dictionary(artists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var owners: [String: UUID] = [:]
        for track in newTracks {
            if let key = track.customArtworkKey { owners[key] = track.id }
            if let key = track.artworkKey, owners[key] == nil { owners[key] = track.id }
        }
        artworkOwners = owners
        revision &+= 1
        onTracksChanged?(removed)
    }
}
