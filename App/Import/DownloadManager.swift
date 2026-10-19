import Foundation
import Observation

enum DownloadError: Error, Equatable, Sendable {
    case invalidURL(DownloadURLError)
    case httpStatus(Int)
    case webPage
    case notAudio(String)
    case unsupportedFormat(String)
    case network(String)
    case insufficientSpace
    case importFailed(ImportError)
}

extension DownloadError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL(let error):
            error.errorDescription
        case .httpStatus(let code):
            String(localized: "Сервер ответил ошибкой \(code). Проверьте, что ссылка ведёт прямо на файл.")
        case .webPage:
            String(localized: "По ссылке открывается веб-страница, а не аудиофайл. Нужна прямая ссылка на файл.")
        case .notAudio(let type):
            String(localized: "По ссылке не аудиофайл (\(type)).")
        case .unsupportedFormat(let ext):
            String(localized: "Формат \(ext) не поддерживается iOS. Подходят MP3, M4A/AAC, ALAC, WAV, AIFF и FLAC.")
        case .network(let reason):
            String(localized: "Ошибка сети: \(reason)")
        case .insufficientSpace:
            String(localized: "Недостаточно места на iPhone для этого файла.")
        case .importFailed(let error):
            error.errorDescription
        }
    }
}

/// Имя сохраняемого файла по ответу сервера: проверка расширения и Content-Type.
enum DownloadNaming {
    static func fileName(requestURL: URL, suggestedFilename: String?, mimeType: String?) -> Result<String, DownloadError> {
        let mime = mimeType ?? ""
        let lowerMIME = mime.lowercased()
        if lowerMIME.hasPrefix("text/html") || lowerMIME.hasPrefix("application/xhtml") {
            return .failure(.webPage)
        }
        let candidates = [suggestedFilename, requestURL.lastPathComponent]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "/" }

        for name in candidates {
            let ext = (name as NSString).pathExtension
            switch AudioFormat.classify(fileExtension: ext) {
            case .supported:
                return .success(name)
            case .unsupported(let unsupported):
                return .failure(.unsupportedFormat(".\(unsupported)"))
            case .notAudio:
                continue
            }
        }
        if let ext = AudioFormat.fileExtension(forMIMEType: mime) {
            let base = candidates.first.map { ($0 as NSString).deletingPathExtension } ?? ""
            return .success("\(base.isEmpty ? "Track" : base).\(ext)")
        }
        if AudioFormat.isUnsupportedAudioMIME(mime) {
            return .failure(.unsupportedFormat(mime))
        }
        return .failure(.notAudio(mime.isEmpty ? String(localized: "тип неизвестен") : mime))
    }
}

/// Делегат URLSession. Неизменяемый — все события уходят в `handler`.
private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    enum Event: Sendable {
        case progress(received: Int64, expected: Int64)
        case staged(file: URL, statusCode: Int?, mimeType: String?, suggestedFilename: String?)
        case failed(DownloadError)
        case cancelled
    }

    private let stagingDirectory: URL
    private let handler: @Sendable (Event) -> Void

    init(stagingDirectory: URL, handler: @escaping @Sendable (Event) -> Void) {
        self.stagingDirectory = stagingDirectory
        self.handler = handler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Без состояния прореживаем события: одно на каждые ~0.5% или 256 КБ.
        let step = max(totalBytesExpectedToWrite / 200, 256 * 1024)
        let crossed = totalBytesWritten / step != (totalBytesWritten - bytesWritten) / step
        if crossed || totalBytesWritten == bytesWritten {
            handler(.progress(received: totalBytesWritten, expected: totalBytesExpectedToWrite))
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Временный файл удаляется сразу после возврата из метода — переносим синхронно.
        let response = downloadTask.response as? HTTPURLResponse
        let staged = stagingDirectory.appending(path: UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: staged)
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            handler(.failed(.insufficientSpace))
            return
        } catch {
            handler(.failed(.network(error.localizedDescription)))
            return
        }
        handler(.staged(file: staged, statusCode: response?.statusCode, mimeType: response?.mimeType,
                        suggestedFilename: response?.suggestedFilename))
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error else { return }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled:
                handler(.cancelled)
            case .notConnectedToInternet:
                handler(.failed(.network(String(localized: "нет подключения к интернету"))))
            case .appTransportSecurityRequiresSecureConnection:
                handler(.failed(.invalidURL(.insecureHTTP)))
            default:
                handler(.failed(.network(urlError.localizedDescription)))
            }
        } else {
            handler(.failed(.network(error.localizedDescription)))
        }
    }
}

/// Загрузка одного файла по ссылке, которую ввёл пользователь.
@MainActor
@Observable
final class DownloadManager {
    enum Phase: Equatable {
        case idle
        case downloading(received: Int64, expected: Int64?)
        case importing
        case finished(fileName: String)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .importing: true
            default: false
            }
        }
    }

    private(set) var phase: Phase = .idle
    /// Открыт ли экран загрузки. Если нет — итог показываем общим алертом.
    @ObservationIgnored var isSheetVisible = false

    @ObservationIgnored private let locations: StorageLocations
    @ObservationIgnored private weak var library: LibraryStore?
    @ObservationIgnored private var session: URLSession?
    @ObservationIgnored private var currentID: UUID?
    @ObservationIgnored private var requestURL: URL?

    init(locations: StorageLocations, library: LibraryStore) {
        self.locations = locations
        self.library = library
        // Недоимпортированные файлы прошлого запуска (приложение могли закрыть посреди загрузки).
        // Синхронно и до первой загрузки, чтобы не удалить уже новый файл.
        try? FileManager.default.removeItem(at: locations.downloads)
    }

    func start(_ text: String) {
        guard !phase.isBusy else { return }
        let url: URL
        switch DownloadURLValidator.validate(text) {
        case .success(let valid):
            url = valid
        case .failure(let error):
            phase = .failed(DownloadError.invalidURL(error).errorDescription ?? "")
            return
        }

        let id = UUID()
        currentID = id
        requestURL = url
        phase = .downloading(received: 0, expected: nil)

        let delegate = DownloadDelegate(stagingDirectory: locations.downloads) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handle(event, id: id)
            }
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.waitsForConnectivity = false
        // Сессия держит делегат сильной ссылкой до invalidate — снимаем в finish().
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: url).resume()
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
        currentID = nil
        phase = .idle
    }

    /// Сбросить результат (после закрытия экрана).
    func reset() {
        guard !phase.isBusy else { return }
        phase = .idle
    }

    private func handle(_ event: DownloadDelegate.Event, id: UUID) {
        guard id == currentID else { return }
        switch event {
        case .progress(let received, let expected):
            let known = expected > 0 ? expected : nil
            if let known, let available = locations.availableCapacity(), known + FileImporter.spaceMargin > available {
                fail(.insufficientSpace)
                return
            }
            phase = .downloading(received: received, expected: known)
        case .staged(let file, let statusCode, let mimeType, let suggested):
            finishSession()
            Task { await self.importStaged(file, statusCode: statusCode, mimeType: mimeType, suggested: suggested, id: id) }
        case .failed(let error):
            fail(error)
        case .cancelled:
            finishSession()
            phase = .idle
        }
    }

    private func importStaged(_ file: URL, statusCode: Int?, mimeType: String?, suggested: String?, id: UUID) async {
        if let statusCode, !(200..<300).contains(statusCode) {
            try? FileManager.default.removeItem(at: file)
            fail(.httpStatus(statusCode))
            return
        }
        guard let requestURL else { return }
        let name: String
        switch DownloadNaming.fileName(requestURL: requestURL, suggestedFilename: suggested, mimeType: mimeType) {
        case .success(let resolved):
            name = resolved
        case .failure(let error):
            try? FileManager.default.removeItem(at: file)
            fail(error)
            return
        }
        guard let library else { return }
        phase = .importing
        let result = await library.importDownloaded(file, fileName: name)
        guard id == currentID else { return }
        currentID = nil
        switch result {
        case .success(let fileName):
            phase = .finished(fileName: fileName)
            if !isSheetVisible {
                library.present(ImportReport(importedPaths: [fileName]))
            }
        case .failure(let error):
            fail(.importFailed(error))
        }
    }

    private func fail(_ error: DownloadError) {
        session?.invalidateAndCancel()
        session = nil
        currentID = nil
        let message = error.errorDescription ?? ""
        phase = .failed(message)
        if !isSheetVisible { library?.notice = message }
    }

    private func finishSession() {
        session?.finishTasksAndInvalidate()
        session = nil
    }
}
