import SwiftUI

/// Фон экрана воспроизведения: «дышащий» градиент из цветов обложки и
/// заранее размытая обложка. Плавно сменяется между треками. Для трека без
/// обложки цвета берутся из его сгенерированной заглушки.
/// Палитра и размытие считаются вне main thread и кэшируются (`ArtworkStore`).
struct DynamicBackground: View {
    let artworkKey: String?
    let seed: String
    let isPlaying: Bool
    /// Насыщенный цвет обложки — для цветной тени под ней.
    @Binding var glowColor: Color

    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var colors = Self.backgroundColors(PaletteExtractor.fallback)
    @State private var backdrop: UIImage?
    @State private var identity = ""

    var body: some View {
        ZStack {
            AuroraMesh(colors: colors, isAnimating: isPlaying && !reduceMotion)
                .id(identity)
                .transition(.opacity)
            if let backdrop, !reduceTransparency {
                Image(uiImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .opacity(DS.Opacity.backdrop)
                    .transition(.opacity)
                    .id(identity)
            }
            LinearGradient(colors: DS.Palette.nowPlayingScrim, startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: "\(artworkKey ?? "")|\(seed)") { await load() }
    }

    private func load() async {
        let palette: [RGBColor]
        let image: UIImage?
        if let key = artworkKey {
            let store = library.artwork
            async let extracted = store.palette(key: key)
            async let blurred = store.backdrop(key: key)
            let loaded = await (extracted, blurred)
            palette = loaded.0
            image = loaded.1
        } else {
            let pair = DS.Palette.placeholderPair(for: seed)
            palette = [pair.0, pair.1]
            image = nil
        }
        guard !Task.isCancelled else { return }
        let newColors = Self.backgroundColors(palette)
        let glow = palette.max { $0.saturation < $1.saturation }.map { Color($0) } ?? DS.Palette.shadow
        withAnimation(DS.Motion.animation(DS.Motion.background, reduceMotion: reduceMotion)) {
            colors = newColors
            backdrop = image
            identity = "\(artworkKey ?? "")|\(seed)"
            glowColor = glow
        }
    }

    /// Три цвета, затемнённые так, чтобы белый текст читался.
    private static func backgroundColors(_ palette: [RGBColor]) -> [Color] {
        let source = palette.isEmpty ? PaletteExtractor.fallback : palette
        var result = source.prefix(DS.Mesh.paletteSize).map { $0.darkened(toLuminance: DS.Palette.backgroundLuminance) }
        while result.count < DS.Mesh.paletteSize, let last = result.last {
            result.append(last.darkened(toLuminance: last.luminance * DS.Palette.meshShade))
        }
        return result.map { Color($0) }
    }
}

/// MeshGradient, который медленно «дышит» во время воспроизведения.
private struct AuroraMesh: View {
    let colors: [Color]
    let isAnimating: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: DS.Motion.ambientFrameInterval, paused: !isAnimating)) { context in
            MeshGradient(
                width: DS.Mesh.width,
                height: DS.Mesh.height,
                points: DS.Mesh.points(at: isAnimating ? context.date.timeIntervalSinceReferenceDate : nil),
                colors: DS.Mesh.colors(colors)
            )
        }
    }
}
