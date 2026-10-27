import Observation

/// Экраны внутри настроек.
enum SettingsRoute: Hashable {
    case appIcon
}

/// Какие модальные экраны открыты. Общий для всех вкладок.
@MainActor
@Observable
final class AppPresenter {
    var showsFilePicker = false
    var showsDownloadSheet = false
    var showsNowPlaying = false
    var showsSettings = false
    /// Навигация внутри настроек; сбрасывается при закрытии.
    var settingsPath: [SettingsRoute] = []
    /// «Сменить обложку» из списков (из «Сейчас играет» — свой лист поверх плеера).
    var artworkEditTarget: ArtworkEditTarget?
}
