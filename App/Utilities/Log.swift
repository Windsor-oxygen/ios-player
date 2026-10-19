import OSLog

/// Локальное журналирование (только системный журнал устройства, без сети).
enum Log {
    static let library = Logger(subsystem: "io.github.windsor-oxygen.player", category: "library")
    static let importing = Logger(subsystem: "io.github.windsor-oxygen.player", category: "import")
    static let playback = Logger(subsystem: "io.github.windsor-oxygen.player", category: "playback")
}
