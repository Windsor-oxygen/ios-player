import Foundation

enum DownloadURLError: Error, Equatable, Sendable {
    case empty
    case malformed
    case insecureHTTP
    case unsupportedScheme(String)
    case unsupportedFormat(String)
}

extension DownloadURLError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .empty:
            String(localized: "Вставьте ссылку на аудиофайл.")
        case .malformed:
            String(localized: "Это не похоже на ссылку. Адрес должен начинаться с https://")
        case .insecureHTTP:
            String(localized: "Ссылки http:// не поддерживаются: соединение не защищено. Попробуйте тот же адрес с https:// в начале.")
        case .unsupportedScheme(let scheme):
            String(localized: "Ссылки вида «\(scheme)://» не поддерживаются. Нужна прямая ссылка https:// на аудиофайл.")
        case .unsupportedFormat(let ext):
            String(localized: "Формат .\(ext) не поддерживается iOS. Подходят MP3, M4A/AAC, ALAC, WAV, AIFF и FLAC.")
        }
    }
}

/// Проверка ссылки, которую ввёл пользователь, до начала загрузки.
enum DownloadURLValidator {
    static func validate(_ text: String) -> Result<URL, DownloadURLError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased() else {
            return .failure(.malformed)
        }
        switch scheme {
        case "https":
            break
        case "http":
            return .failure(.insecureHTTP)
        default:
            return .failure(.unsupportedScheme(scheme))
        }
        guard let host = components.host, !host.isEmpty, let url = components.url else {
            return .failure(.malformed)
        }
        let ext = url.pathExtension
        if !ext.isEmpty {
            switch AudioFormat.classify(fileExtension: ext) {
            case .supported:
                break
            case .unsupported(let unsupported):
                return .failure(.unsupportedFormat(unsupported))
            case .notAudio:
                // Расширение может быть «.php» и т. п. — решит Content-Type ответа.
                break
            }
        }
        return .success(url)
    }
}
