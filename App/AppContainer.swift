import Foundation

/// Создаёт и связывает сервисы приложения. Живёт всё время работы приложения.
@MainActor
final class AppContainer {
    let settings = AppSettings()
    let library: LibraryStore
    let playback: PlaybackEngine
    let downloads: DownloadManager
    let presenter = AppPresenter()

    init(locations: StorageLocations = .standard) {
        library = LibraryStore(locations: locations)
        playback = PlaybackEngine(library: library, settings: settings, locations: locations)
        downloads = DownloadManager(locations: locations, library: library)
        // Слабая ссылка: библиотека не должна удерживать движок.
        library.onTracksChanged = { [weak playback] removed in
            playback?.libraryDidChange(removed: removed)
        }
    }
}
