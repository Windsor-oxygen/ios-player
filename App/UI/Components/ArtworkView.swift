import SwiftUI

/// Обложка из кэша. Без обложки — сгенерированная заглушка (градиент + первая
/// буква). Загрузка и декодирование — вне main thread.
struct ArtworkView: View {
    let key: String?
    /// Из чего строится заглушка: обычно название трека, альбома или исполнителя.
    var seed = ""
    var size: ArtworkStore.Size = .small
    var cornerRadius = DS.Radius.s

    @Environment(LibraryStore.self) private var library
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else {
                GeneratedArtwork(seed: seed)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
        .task(id: key) {
            guard let key else {
                image = nil
                return
            }
            // Если миниатюры нет на диске, библиотека пересоздаст её из источника.
            let loaded = await library.artworkImage(key: key, size: size)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

/// Заглушка для трека без обложки: градиент и значок выбираются по id трека
/// (альбома, исполнителя) и одинаковы при каждом показе.
/// Всё вычисляется один раз в `init`, а не в `body`.
struct GeneratedArtwork: View {
    private let colors: [Color]
    private let symbol: String

    init(seed: String) {
        let pair = DS.Palette.placeholderPair(for: seed)
        colors = [Color(pair.0), Color(pair.1)]
        symbol = DS.Palette.placeholderSymbol(for: seed)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(
                    colors: [DS.Palette.onArtwork.opacity(DS.Opacity.soft), .clear],
                    center: .topLeading, startRadius: 0, endRadius: side
                )
                Image(systemName: symbol)
                    .font(DS.Font.placeholderSymbol(side: side))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(DS.Palette.onArtwork.opacity(DS.Opacity.strong))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
