import Observation

/// Какие модальные экраны открыты. Общий для всех вкладок.
@MainActor
@Observable
final class AppPresenter {
    var showsFilePicker = false
    var showsDownloadSheet = false
    var showsNowPlaying = false
    var showsSettings = false
}
