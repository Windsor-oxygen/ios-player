import SwiftUI

/// Фон экрана воспроизведения: градиент из доминантных цветов обложки
/// и заранее размытая обложка. Плавно меняется при смене трека.
struct DynamicBackground: View {
    let artworkKey: String?

    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var colors = PaletteExtractor.fallback
    @State private var backdrop: UIImage?

    var body: some View {
        ZStack {
            LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            if let backdrop {
                Image(uiImage: backdrop)
                    .resizable()
                    .scaledToFill()
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
                    .opacity(0.55)
                    .transition(.opacity)
                    .id(artworkKey)
            }
            // Затемнение снизу — чтобы элементы управления читались на любой обложке.
            LinearGradient(
                colors: [.black.opacity(0.15), .black.opacity(0.35), .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .task(id: artworkKey) {
            let animation: Animation? = reduceMotion ? nil : .easeInOut(duration: 0.8)
            guard let key = artworkKey else {
                withAnimation(animation) {
                    colors = PaletteExtractor.fallback
                    backdrop = nil
                }
                return
            }
            let store = library.artwork
            async let palette = store.palette(key: key)
            async let image = store.backdrop(key: key)
            let (newColors, newBackdrop) = await (palette, image)
            guard !Task.isCancelled else { return }
            withAnimation(animation) {
                colors = newColors
                backdrop = newBackdrop
            }
        }
    }

    private var gradientColors: [Color] {
        let palette = colors.count >= 2 ? colors : PaletteExtractor.fallback
        return palette.prefix(3).map { color in
            let dark = color.darkened(toLuminance: 0.28)
            return Color(red: dark.red, green: dark.green, blue: dark.blue)
        }
    }
}
