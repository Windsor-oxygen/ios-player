import Foundation

/// Какие файлы приложение принимает. AVFoundation на iOS декодирует MP3,
/// AAC/ALAC (m4a), WAV, AIFF, FLAC и CAF; Ogg Vorbis/Opus, WMA и APE — нет.
enum AudioFormat {
    enum Classification: Equatable, Sendable {
        case supported
        /// Аудио, которое iOS не умеет декодировать (ogg, opus, wma…).
        case unsupported(String)
        /// Не аудиофайл вовсе.
        case notAudio
    }

    static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "mp4", "alac", "wav", "wave",
        "aif", "aiff", "aifc", "flac", "caf",
    ]

    static let knownUnsupportedExtensions: Set<String> = [
        "ogg", "oga", "opus", "wma", "ape", "mka", "webm", "dsf", "dff", "mid", "midi", "ra", "amr",
    ]

    static func classify(fileExtension: String) -> Classification {
        let ext = fileExtension.lowercased()
        if supportedExtensions.contains(ext) { return .supported }
        if knownUnsupportedExtensions.contains(ext) { return .unsupported(ext) }
        return .notAudio
    }

    static func classify(_ url: URL) -> Classification {
        classify(fileExtension: url.pathExtension)
    }

    static func isSupported(_ url: URL) -> Bool {
        classify(url) == .supported
    }

    /// Расширение по MIME-типу ответа сервера. `nil` — тип не аудио
    /// или универсальный (`application/octet-stream`).
    static func fileExtension(forMIMEType mime: String) -> String? {
        mimeToExtension[normalizedMIME(mime)]
    }

    static func isUnsupportedAudioMIME(_ mime: String) -> Bool {
        let type = normalizedMIME(mime)
        return (type.hasPrefix("audio/") && mimeToExtension[type] == nil)
            || ["application/ogg", "video/webm"].contains(type)
    }

    private static func normalizedMIME(_ mime: String) -> String {
        let base = mime.split(separator: ";", maxSplits: 1).first.map(String.init) ?? mime
        return base.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static let mimeToExtension: [String: String] = [
        "audio/mpeg": "mp3",
        "audio/mp3": "mp3",
        "audio/mpeg3": "mp3",
        "audio/x-mpeg-3": "mp3",
        "audio/mp4": "m4a",
        "audio/m4a": "m4a",
        "audio/x-m4a": "m4a",
        "audio/aac": "aac",
        "audio/x-aac": "aac",
        "audio/aacp": "aac",
        "audio/wav": "wav",
        "audio/x-wav": "wav",
        "audio/wave": "wav",
        "audio/vnd.wave": "wav",
        "audio/aiff": "aiff",
        "audio/x-aiff": "aiff",
        "audio/flac": "flac",
        "audio/x-flac": "flac",
        "audio/x-caf": "caf",
    ]
}
