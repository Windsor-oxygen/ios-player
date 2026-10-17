import Foundation
import Observation

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

    /// Параллельных чтений метаданных: больше — без выигрыша на A13 и с риском подтормаживаний.
    private static let metadataConcurrency = 4
    /// Сколько результатов копить перед обновлением UI.
    private static let metadataBatch = 25

    init(locations: StorageLocations) {
        self.locations = locations
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
        switch await persistence.load() {
        case .loaded(let index):
            playlists = index.playlists
            setTracks(index.tracks)
        case .empty:
            break
        case .recoveredFromCorruption:
            notice = String(localized: "Файл библиотеки был повреждён и создан заново. Музыкальные файлы не пострадали — они будут найдены повторно, но плейлисты потеряны.")
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
        if !inboxReport.importedPaths.isEmpty || !inboxReport.failures.isEmpty {
            present(inboxReport)
        }
    }

    private nonisolated static func scan(_ locations: StorageLocations) async -> [ScannedFile] {
        FolderScanner.scan(locations)
    }

    private struct ProcessedMetadata: Sendable {
        let id: UUID
        let metadata: TrackMetadata
        let artworkKey: String?
    }

    private nonisolated static func process(id: UUID, url: URL, artwork: ArtworkStore) async -> ProcessedMetadata {
        var metadata = await MetadataLoader.load(url: url)
        let key = metadata.artworkData.flatMap { artwork.store(imageData: $0) }
        metadata.artworkData = nil
        return ProcessedMetadata(id: id, metadata: metadata, artworkKey: key)
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
            track.title = meta.title ?? Track.defaultTitle(forRelativePath: track.relativePath)
            track.artist = meta.artist
            track.album = meta.album
            track.trackNumber = meta.trackNumber
            track.discNumber = meta.discNumber
            track.duration = meta.duration
            track.artworkKey = result.artworkKey
            track.isUnplayable = !meta.isPlayable
            track.needsMetadata = false
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

    private func present(_ report: ImportReport) {
        if var existing = lastReport {
            existing.importedPaths += report.importedPaths
            existing.failures += report.failures
            lastReport = existing
        } else {
            lastReport = report
        }
    }

    // MARK: - Deletion

    /// Удаляет файлы с диска и записи из библиотеки и плейлистов.
    func delete(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        let urls = tracks.filter { ids.contains($0.id) }.map { locations.fileURL(forRelativePath: $0.relativePath) }
        await Self.removeFiles(urls)
        setTracks(tracks.filter { !ids.contains($0.id) })
        for index in playlists.indices {
            playlists[index].trackIDs.removeAll { ids.contains($0) }
        }
        scheduleSave()
        let keys = Set(tracks.compactMap(\.artworkKey))
        let artwork = self.artwork
        Task.detached(priority: .utility) { artwork.removeUnreferenced(keeping: keys) }
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
        revision &+= 1
        onTracksChanged?(removed)
    }
}
