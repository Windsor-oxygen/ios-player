import Foundation

/// Аудиофайл, найденный на диске.
struct ScannedFile: Equatable, Sendable {
    let relativePath: String
    let fileSize: Int64
    let modificationDate: Date
}

/// Обход Documents (рекурсивно, без скрытых файлов, Inbox и «Не импортировано»).
enum FolderScanner {
    static func scan(_ locations: StorageLocations) -> [ScannedFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: locations.documents,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        let skipped = Set([locations.inbox, locations.notImported].map(canonicalPath))
        var result: [ScannedFile] = []
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true {
                if skipped.contains(canonicalPath(url)) { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true,
                  AudioFormat.isSupported(url),
                  let relative = locations.relativePath(of: url) else { continue }
            result.append(ScannedFile(
                relativePath: relative,
                fileSize: Int64(values.fileSize ?? 0),
                modificationDate: values.contentModificationDate ?? .distantPast
            ))
        }
        return result
    }

    /// Путь без симлинков и завершающего «/» — для сравнения папок.
    private static func canonicalPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

/// Сверка индекса с тем, что реально лежит на диске. Чистая функция — покрыта тестами.
enum LibraryReconciler {
    struct Result: Equatable, Sendable {
        var tracks: [Track]
        var addedCount: Int
        var missingCount: Int
    }

    static func reconcile(existing: [Track], scanned: [ScannedFile], now: Date = .now) -> Result {
        var byPath: [String: ScannedFile] = [:]
        for file in scanned { byPath[file.relativePath] = file }

        var tracks: [Track] = []
        tracks.reserveCapacity(max(existing.count, scanned.count))
        var seen = Set<String>()
        var missing = 0

        for var track in existing {
            // Дубликаты путей в индексе (не должны появляться, но индекс мог быть правлен руками).
            guard seen.insert(track.relativePath).inserted else { continue }
            if let file = byPath[track.relativePath] {
                let changed = file.fileSize != track.fileSize
                    || abs(file.modificationDate.timeIntervalSince(track.modificationDate)) > 1
                if track.isMissing || changed {
                    track.isMissing = false
                    if changed {
                        track.fileSize = file.fileSize
                        track.modificationDate = file.modificationDate
                        track.isUnplayable = false
                        track.needsMetadata = true
                    }
                }
            } else {
                if !track.isMissing { track.isMissing = true }
                missing += 1
            }
            tracks.append(track)
        }

        var added = 0
        for file in scanned where !seen.contains(file.relativePath) {
            seen.insert(file.relativePath)
            added += 1
            tracks.append(Track(
                id: UUID(),
                relativePath: file.relativePath,
                title: Track.defaultTitle(forRelativePath: file.relativePath),
                artist: nil,
                album: nil,
                trackNumber: nil,
                discNumber: nil,
                duration: 0,
                fileSize: file.fileSize,
                modificationDate: file.modificationDate,
                dateAdded: now,
                artworkKey: nil,
                isMissing: false,
                isUnplayable: false,
                needsMetadata: true
            ))
        }
        return Result(tracks: tracks, addedCount: added, missingCount: missing)
    }
}
