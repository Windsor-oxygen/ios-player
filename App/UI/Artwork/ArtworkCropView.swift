import SwiftUI

/// Квадратная обрезка: щипок — масштаб, перетаскивание — сдвиг.
/// Квадрат не выходит за края картинки.
struct ArtworkCropView: View {
    let image: UIImage
    let isSaving: Bool
    /// Видимый квадрат в пикселях картинки.
    let onDone: (CGRect) -> Void

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var viewSide: CGFloat = 0
    @GestureState private var pinch: CGFloat = 1
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        VStack(spacing: DS.Spacing.l) {
            GeometryReader { proxy in
                let side = min(proxy.size.width, proxy.size.height)
                let liveZoom = clampZoom(zoom * pinch)
                let liveOffset = ArtworkEditing.clampedOffset(
                    CGSize(width: offset.width + drag.width, height: offset.height + drag.height),
                    imageSize: pixelSize, viewSide: side, zoom: liveZoom
                )
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .scaleEffect(liveZoom)
                    .offset(liveOffset)
                    .frame(width: side, height: side)
                    .clipped()
                    .overlay { CropGrid() }
                    .contentShape(Rectangle())
                    .gesture(cropGesture(side: side))
                    .onAppear { viewSide = side }
                    .onChange(of: side) { _, newSide in viewSide = newSide }
                    .accessibilityElement()
                    .accessibilityLabel("Область обрезки")
                    .accessibilityHint("Сведите или разведите пальцы, чтобы изменить масштаб, и перетащите, чтобы сдвинуть.")
            }
            .aspectRatio(1, contentMode: .fit)

            Text("Сдвиньте и увеличьте картинку, чтобы выбрать квадрат.")
                .font(DS.Font.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button {
                onDone(ArtworkEditing.cropRect(imageSize: pixelSize, viewSide: viewSide, zoom: zoom, offset: offset))
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Готово")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .font(DS.Font.bodyEmphasized)
            .disabled(isSaving || viewSide <= 0)
        }
        .padding(DS.Spacing.l)
    }

    private var pixelSize: CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    private func clampZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 1), DS.Crop.maxZoom)
    }

    private func cropGesture(side: CGFloat) -> some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    zoom = clampZoom(zoom * value.magnification)
                    offset = ArtworkEditing.clampedOffset(offset, imageSize: pixelSize, viewSide: side, zoom: zoom)
                },
            DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    let moved = CGSize(width: offset.width + value.translation.width,
                                       height: offset.height + value.translation.height)
                    offset = ArtworkEditing.clampedOffset(moved, imageSize: pixelSize, viewSide: side, zoom: zoom)
                }
        )
    }
}

/// Рамка и сетка третей поверх области обрезки.
private struct CropGrid: View {
    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                ForEach(0..<DS.Crop.gridDivisions, id: \.self) { _ in
                    Rectangle().strokeBorder(DS.Palette.onArtwork.opacity(DS.Opacity.hairline), lineWidth: DS.Stroke.hairline)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<DS.Crop.gridDivisions, id: \.self) { _ in
                    Rectangle().strokeBorder(DS.Palette.onArtwork.opacity(DS.Opacity.hairline), lineWidth: DS.Stroke.hairline)
                }
            }
            Rectangle()
                .strokeBorder(DS.Palette.onArtwork, lineWidth: DS.Stroke.hairline * DS.Stroke.ringScale)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
