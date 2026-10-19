import SwiftUI

/// Обложка из кэша с заглушкой. Загрузка и декодирование — вне main thread.
struct ArtworkView: View {
    let key: String?
    var size: ArtworkStore.Size = .small
    var cornerRadius: CGFloat = 6
    /// Отключить заглушку «♪» (например, пока грузится обложка поверх другого фона).
    var showsPlaceholder = true

    @Environment(LibraryStore.self) private var library
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            } else if showsPlaceholder {
                ArtworkPlaceholder()
            } else {
                Color.clear
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

/// Заглушка для трека без обложки.
struct ArtworkPlaceholder: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.24), Color(white: 0.14)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: proxy.size.width * 0.36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}
