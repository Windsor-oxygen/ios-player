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
            let loaded = await library.artwork.image(key: key, size: size)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

/// Заглушка для трека без обложки: цвета и буква стабильны для одного названия.
/// Всё вычисляется один раз в `init`, а не в `body`.
struct GeneratedArtwork: View {
    private let colors: [Color]
    private let letter: String?

    init(seed: String) {
        let pair = DS.Palette.placeholderPair(for: seed)
        colors = [Color(pair.0), Color(pair.1)]
        letter = seed.first(where: \.isLetter).map { String($0).uppercased() }
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
                if let letter {
                    Text(letter)
                        .font(DS.Font.placeholderLetter(side: side))
                        .foregroundStyle(DS.Palette.onArtwork.opacity(DS.Opacity.strong))
                } else {
                    Image(systemName: "music.note")
                        .font(DS.Font.placeholderSymbol(side: side))
                        .foregroundStyle(DS.Palette.onArtworkSecondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}
