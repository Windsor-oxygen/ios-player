#if DEBUG
import UIKit

/// Демонстрационные данные для скриншотов в CI.
///
/// Только Debug-сборка: в Release этого кода и launch argument нет (CI это
/// проверяет). Работает в отдельной временной папке и отдельном UserDefaults —
/// реальные музыка, библиотека и настройки не затрагиваются.
///
/// Запуск: `-PlayerDemo library|nowPlaying|settings|icons|empty`
/// и необязательно `-PlayerDemoAppearance dark|light`.
struct DemoMode {
    enum Screen: String {
        case library
        case nowPlaying
        case settings
        case icons
        case empty
    }

    let screen: Screen
    let appearance: AppearanceMode

    static func fromLaunchArguments() -> DemoMode? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let screen = value(after: "-PlayerDemo", in: arguments).flatMap(Screen.init(rawValue:)) else {
            return nil
        }
        let appearance = value(after: "-PlayerDemoAppearance", in: arguments).flatMap(AppearanceMode.init(rawValue:))
        return DemoMode(screen: screen, appearance: appearance ?? .dark)
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    @MainActor
    func makeContainer() -> AppContainer {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appending(path: "PlayerDemo", directoryHint: .isDirectory)
        // Удаляется только собственная временная папка демо-режима.
        try? fm.removeItem(at: root)
        let locations = StorageLocations(
            documents: root.appending(path: "Documents", directoryHint: .isDirectory),
            applicationSupport: root.appending(path: "Support", directoryHint: .isDirectory),
            caches: root.appending(path: "Caches", directoryHint: .isDirectory)
        )
        let suite = "PlayerDemo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        if screen != .empty {
            DemoLibrary.write(to: locations)
        }
        let container = AppContainer(locations: locations, defaults: defaults)
        container.settings.appearance = appearance
        return container
    }

    /// Открывает нужный экран после загрузки библиотеки.
    @MainActor
    static func present(in container: AppContainer) async {
        guard let demo = fromLaunchArguments() else { return }
        await container.library.refresh()
        await container.playback.restore()
        switch demo.screen {
        case .library:
            container.playback.play()
        case .nowPlaying:
            container.playback.play()
            container.presenter.showsNowPlaying = true
        case .settings:
            container.presenter.showsSettings = true
        case .icons:
            container.presenter.settingsPath = [.appIcon]
            container.presenter.showsSettings = true
        case .empty:
            break
        }
    }
}

/// Вымышленная библиотека: альбомы с нарисованными обложками, песни без
/// обложки, очень длинные названия, отсутствующий файл, плейлисты и очередь.
private enum DemoLibrary {
    struct Album: Sendable {
        let title: String?
        let artist: String?
        let colors: (UInt32, UInt32)?
        let songs: [String]
    }

    static let albums: [Album] = [
        Album(title: "Северное сияние", artist: "Полярный экспресс", colors: (0x3A1C71, 0xD76D77),
              songs: ["Северное сияние", "Ледяной ветер", "Огни над тундрой", "Тишина", "Утро на станции", "Домой"]),
        Album(title: "Neon Nights", artist: "Synth Avenue", colors: (0x0F0C29, 0xFF2BD6),
              songs: ["Neon Nights", "Night Drive", "Afterglow", "Chrome Hearts", "Skyline"]),
        Album(title: "Ocean Drive", artist: "Blue Harbor", colors: (0x00467F, 0xA5CC82),
              songs: ["Low Tide", "Salt & Sun", "Harbor Lights", "Paper Boats", "Undertow"]),
        Album(title: "Тёплый ламповый", artist: "Квартет «Вечер»", colors: (0xF09819, 0xEDDE5D),
              songs: ["Старый город", "Кофе в восемь", "Дождь по крыше", "Вальс"]),
        Album(title: "Midnight Jazz Sessions", artist: "The Late Trio", colors: (0x232526, 0x9D50BB),
              songs: ["Blue in Green Room", "Smoke Rings", "Last Call", "Moonlit Steps", "Coda"]),
        Album(title: "Горные тропы", artist: "Эхо", colors: (0x134E5E, 0x71B280),
              songs: ["Перевал", "Река", "Туман", "Вершина"]),
        Album(title: nil, artist: "Исполнитель с невероятно длинным именем, которое не помещается никуда",
              colors: nil,
              songs: ["Очень длинное название песни, которое никак не помещается в одну строку и должно аккуратно обрезаться",
                      "Без обложки", "Демо-запись", "Импровизация"]),
    ]

    static func write(to locations: StorageLocations) {
        let fm = FileManager.default
        try? fm.createDirectory(at: locations.music, withIntermediateDirectories: true)
        let artwork = ArtworkStore(directory: locations.artwork)
        let shortSilence = silence(seconds: 1)
        var tracks: [Track] = []
        var added = Date(timeIntervalSinceReferenceDate: 780_000_000)

        for (albumIndex, album) in albums.enumerated() {
            let key = album.colors.flatMap { cover($0.0, $0.1, motif: albumIndex) }.flatMap { artwork.store(imageData: $0) }
            for (songIndex, song) in album.songs.enumerated() {
                let isCurrent = tracks.isEmpty
                let path = "Music/\(album.title ?? "Синглы")/\(songIndex + 1) \(song.prefix(40)).wav"
                let url = locations.fileURL(forRelativePath: path)
                let data = isCurrent ? silence(seconds: 240) : shortSilence
                try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                added.addTimeInterval(3600)
                tracks.append(Track(
                    id: UUID(),
                    relativePath: path,
                    title: song,
                    artist: album.artist,
                    album: album.title,
                    trackNumber: album.title == nil ? nil : songIndex + 1,
                    discNumber: nil,
                    duration: isCurrent ? 240 : TimeInterval(150 + (albumIndex * 37 + songIndex * 23) % 140),
                    fileSize: Int64(data.count),
                    modificationDate: modified ?? .now,
                    dateAdded: added,
                    artworkKey: key,
                    isMissing: false,
                    isUnplayable: false,
                    needsMetadata: false
                ))
            }
        }
        // Файл, удалённый через «Файлы»: в библиотеке остаётся помеченным.
        tracks.append(Track(
            id: UUID(), relativePath: "Music/Удалённая песня.mp3", title: "Удалённая песня", artist: "Эхо",
            album: nil, trackNumber: nil, discNumber: nil, duration: 200, fileSize: 1, modificationDate: .now,
            dateAdded: added, artworkKey: nil, isMissing: true, isUnplayable: false, needsMetadata: false
        ))

        let ids = tracks.map(\.id)
        let playlists = [
            Playlist(name: "Любимое", trackIDs: stride(from: 0, to: ids.count, by: 3).map { ids[$0] }),
            Playlist(name: "В дорогу", trackIDs: Array(ids.dropFirst(6).prefix(10))),
            Playlist(name: "Для работы"),
        ]
        let index = LibraryIndex(tracks: tracks, playlists: playlists)
        var queue = PlaybackQueue()
        queue.replace(with: Array(ids.prefix(6)), startAt: 0, shuffled: false)
        let snapshot = PlaybackSnapshot(queue: queue, position: 74)
        try? fm.createDirectory(at: locations.applicationSupport, withIntermediateDirectories: true)
        try? JSONEncoder().encode(index).write(to: locations.libraryIndex)
        try? JSONEncoder().encode(snapshot).write(to: locations.playbackState)
    }

    /// Обложка: градиент и простой геометрический мотив.
    private static func cover(_ top: UInt32, _ bottom: UInt32, motif: Int) -> Data? {
        let side: CGFloat = 600
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            let cg = context.cgContext
            let colors = [color(top).cgColor, color(bottom).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            UIColor.white.withAlphaComponent(0.22).setStroke()
            UIColor.white.withAlphaComponent(0.16).setFill()
            cg.setLineWidth(10)
            switch motif % 3 {
            case 0:
                for step in 1...6 {
                    let inset = CGFloat(step) * 45
                    cg.strokeEllipse(in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
                }
            case 1:
                for step in stride(from: -side, to: side, by: 70) {
                    cg.move(to: CGPoint(x: step, y: side))
                    cg.addLine(to: CGPoint(x: step + side, y: 0))
                }
                cg.strokePath()
            default:
                cg.fillEllipse(in: CGRect(x: side * 0.25, y: side * 0.18, width: side * 0.5, height: side * 0.5))
                for line in 0..<5 {
                    let y = side * 0.62 + CGFloat(line) * 34
                    cg.fill(CGRect(x: 0, y: y, width: side, height: 14))
                }
            }
        }
        return image.jpegData(compressionQuality: 0.9)
    }

    private static func color(_ hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// WAV с тишиной (16 бит, моно, 8 кГц).
    private static func silence(seconds: Int) -> Data {
        let sampleRate = 8000
        let dataSize = sampleRate * seconds * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))
        append(UInt16(2))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
#endif
