import AVFoundation

struct TrackMetadata: Sendable {
    var title: String?
    var artist: String?
    var album: String?
    var trackNumber: Int?
    var discNumber: Int?
    var duration: TimeInterval
    var isPlayable: Bool
    var artworkData: Data?

    static let unplayable = TrackMetadata(duration: 0, isPlayable: false)
}

/// Результат чтения обложки из тегов файла.
enum ArtworkRead: Equatable, Sendable {
    case found(Data)
    /// Файл прочитан, обложки в нём нет.
    case absent
    /// Файл прочитать не удалось — прежнюю обложку не трогаем.
    case failed
}

/// Откуда брать обложку из тегов аудиофайла (в тестах подменяется).
struct ArtworkReader: Sendable {
    let read: @Sendable (URL) async -> ArtworkRead

    static let tags = ArtworkReader { await MetadataLoader.loadArtwork(url: $0) }
}

/// Асинхронное чтение тегов через AVURLAsset. Вызывается вне main thread.
/// Файлы только читаются — в аудиофайлы приложение ничего не пишет.
enum MetadataLoader {
    static func load(url: URL) async -> TrackMetadata {
        let asset = AVURLAsset(url: url)
        let common: [AVMetadataItem]
        let duration: CMTime
        let playable: Bool
        do {
            let values = try await asset.load(.commonMetadata, .duration, .isPlayable)
            common = values.0
            duration = values.1
            playable = values.2
        } catch {
            Log.library.notice("Не удалось прочитать \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .unplayable
        }
        guard playable else { return .unplayable }

        var result = TrackMetadata(
            duration: duration.isNumeric ? max(0, duration.seconds) : 0,
            isPlayable: true
        )
        result.title = await string(in: common, .commonIdentifierTitle)
        result.artist = await string(in: common, .commonIdentifierArtist)
        result.album = await string(in: common, .commonIdentifierAlbumName)
        if let artwork = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first {
            result.artworkData = try? await artwork.load(.dataValue)
        }

        // Номер трека и диска не входят в common-набор — ищем в форматных тегах.
        if let all = try? await asset.load(.metadata) {
            result.trackNumber = await number(in: all, identifiers: [.iTunesMetadataTrackNumber, .id3MetadataTrackNumber])
            result.discNumber = await number(in: all, identifiers: [.iTunesMetadataDiscNumber, .id3MetadataPartOfASet])
            if result.artist == nil {
                result.artist = await string(in: all, .iTunesMetadataAlbumArtist)
            }
        }
        return result
    }

    /// Только обложка — для восстановления пропавших миниатюр.
    static func loadArtwork(url: URL) async -> ArtworkRead {
        guard let common = try? await AVURLAsset(url: url).load(.commonMetadata) else { return .failed }
        guard let item = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierArtwork).first else {
            return .absent
        }
        guard let data = try? await item.load(.dataValue), !data.isEmpty else { return .failed }
        return .found(data)
    }

    private static func string(in items: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func number(in items: [AVMetadataItem], identifiers: [AVMetadataIdentifier]) async -> Int? {
        for identifier in identifiers {
            guard let item = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier).first else {
                continue
            }
            // ID3: строка «3/12»; iTunes: бинарные данные, номер — в байтах 2…3.
            if let text = try? await item.load(.stringValue), let parsed = parseTrackNumber(text) {
                return parsed
            }
            if let data = try? await item.load(.dataValue), data.count >= 4 {
                let value = Int(data[data.startIndex + 2]) << 8 | Int(data[data.startIndex + 3])
                if value > 0 { return value }
            }
            if let number = try? await item.load(.numberValue), number.intValue > 0 {
                return number.intValue
            }
        }
        return nil
    }

    /// «3», «03», «3/12» → 3.
    static func parseTrackNumber(_ text: String) -> Int? {
        let head = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        guard let value = Int(head.trimmingCharacters(in: .whitespaces)), value > 0 else { return nil }
        return value
    }
}
