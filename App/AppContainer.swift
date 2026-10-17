import Foundation

/// Создаёт и связывает сервисы приложения. Живёт всё время работы приложения.
@MainActor
final class AppContainer {
    let library: LibraryStore
    let downloads: DownloadManager
    let importPresenter = ImportPresenter()

    init(locations: StorageLocations = .standard) {
        library = LibraryStore(locations: locations)
        downloads = DownloadManager(locations: locations, library: library)
    }
}
