import Foundation

/// Резервные копии служебных файлов (Library.json, Playback.json).
/// Только копирование: исходник и прежние копии не удаляются и не перезаписываются.
enum FileBackup {
    /// Копирует файл рядом с ним: `Library.json.backup-20261019-153012`.
    /// `nil` — копию сделать не удалось (тогда исходник перезаписывать нельзя).
    static func makeCopy(of url: URL) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "\(url.lastPathComponent).backup-\(formatter.string(from: .now))"
        let directory = url.deletingLastPathComponent()
        let fm = FileManager.default
        var candidate = directory.appending(path: base)
        var counter = 2
        while fm.fileExists(atPath: candidate.path(percentEncoded: false)) {
            candidate = directory.appending(path: "\(base)-\(counter)")
            counter += 1
        }
        do {
            try fm.copyItem(at: url, to: candidate)
            Log.storage.notice("Резервная копия: \(candidate.lastPathComponent, privacy: .public)")
            return candidate
        } catch {
            Log.storage.error("Не удалось сделать копию \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
