import Observation

/// Какие экраны импорта открыты. Общий для всех вкладок.
@MainActor
@Observable
final class ImportPresenter {
    var showsFilePicker = false
    var showsDownloadSheet = false
}
