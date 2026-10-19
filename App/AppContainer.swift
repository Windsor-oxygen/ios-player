import Foundation

/// Создаёт и связывает сервисы приложения. Живёт всё время работы приложения.
@MainActor
final class AppContainer {
    let settings: AppSettings
    let library: LibraryStore
    let playback: PlaybackEngine
    let downloads: DownloadManager
    let presenter = AppPresenter()
    let appIcons = AppIconController()
    /// Хранилище настроек, в том числе для `@AppStorage`.
    let defaults: UserDefaults

    init(locations: StorageLocations = .standard, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AppSettings(defaults: defaults)
        library = LibraryStore(locations: locations)
        playback = PlaybackEngine(library: library, settings: settings, locations: locations)
        downloads = DownloadManager(locations: locations, library: library)
        // Слабая ссылка: библиотека не должна удерживать движок.
        library.onTracksChanged = { [weak playback] removed in
            playback?.libraryDidChange(removed: removed)
        }
    }

    /// Контейнер для запуска приложения. В Debug-сборке launch argument
    /// `-PlayerDemo` подменяет данные демонстрационными (для скриншотов в CI).
    static func launch() -> AppContainer {
        #if DEBUG
        if let demo = DemoMode.fromLaunchArguments() {
            return demo.makeContainer()
        }
        #endif
        return AppContainer()
    }
}
