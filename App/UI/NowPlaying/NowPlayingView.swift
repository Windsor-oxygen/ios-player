import SwiftUI

/// Полноэкранный плеер. Фон всегда тёмный (из цветов обложки), поэтому
/// экран использует тёмную схему в обеих темах приложения.
struct NowPlayingView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsQueue = false
    @State private var dragOffset: CGFloat = 0
    @State private var glowColor = DS.Palette.shadow
    @State private var artworkTarget: ArtworkEditTarget?

    var body: some View {
        ZStack {
            if let track = engine.currentTrack {
                content(track)
            } else {
                EmptyStateView(symbol: "music.note", title: "Ничего не играет")
            }
        }
        .foregroundStyle(DS.Palette.onArtwork)
        // Фон через .background, чтобы растянутая обложка не влияла на раскладку.
        .background {
            DynamicBackground(
                artworkKey: engine.currentTrack?.displayArtworkKey,
                seed: engine.currentTrack?.id.uuidString ?? "",
                isPlaying: engine.isPlaying,
                glowColor: $glowColor
            )
        }
        .overlay(alignment: .top) { MessageBanner(message: engine.message) }
        .offset(y: dragOffset)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showsQueue) { QueueView() }
        .sheet(item: $artworkTarget) { ArtworkEditorSheet(target: $0) }
    }

    private func content(_ track: Track) -> some View {
        VStack(spacing: DS.Spacing.l) {
            header(track)
            // Обложка занимает всё оставшееся место и остаётся квадратной.
            artwork(track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            titles(track)
            ScrubberView()
            TransportControls()
            volumeRow
            secondaryControls
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.bottom, DS.Spacing.l)
    }

    private func header(_ track: Track) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(DS.Font.controlIcon)
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            }
            .accessibilityLabel("Свернуть плеер")
            Spacer()
            Capsule()
                .fill(DS.Palette.onArtworkTertiary)
                .frame(width: DS.Size.grabber.width, height: DS.Size.grabber.height)
                .accessibilityHidden(true)
            Spacer()
            Menu {
                Button {
                    artworkTarget = ArtworkEditTarget(trackIDs: [track.id], title: track.title, isAlbum: false)
                } label: {
                    Label("Сменить обложку…", systemImage: "photo")
                }
                if track.customArtworkKey != nil {
                    Button {
                        Task { await library.resetCustomArtwork(for: [track.id]) }
                    } label: {
                        Label("Сбросить обложку", systemImage: "arrow.uturn.backward")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(DS.Font.controlIcon)
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            }
            .accessibilityLabel("Действия с треком")
        }
        .padding(.top, DS.Spacing.s)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private func artwork(_ track: Track) -> some View {
        ArtworkView(key: track.displayArtworkKey, seed: track.id.uuidString, size: .large, cornerRadius: DS.Radius.xxl)
            .dsShadow(engine.isPlaying ? DS.Shadow.artworkPlaying : DS.Shadow.artworkPaused, color: glowColor)
            .scaleEffect(engine.isPlaying ? 1 : DS.Scale.artworkPaused)
            .animation(DS.Motion.animation(DS.Motion.artwork, reduceMotion: reduceMotion), value: engine.isPlaying)
            .padding(DS.Spacing.s)
            .id(track.id)
            .transition(.opacity)
            .animation(DS.Motion.animation(DS.Motion.trackChange, reduceMotion: reduceMotion), value: track.id)
            .gesture(dismissDrag)
    }

    private func titles(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(track.title)
                .font(DS.Font.title)
                .lineLimit(DS.LineLimit.nowPlayingTitle)
            Text(track.artist ?? LibraryQuery.unknownArtist)
                .font(DS.Font.subtitle)
                .foregroundStyle(DS.Palette.onArtworkSecondary)
                .lineLimit(DS.LineLimit.rowTitle)
            if let album = track.album {
                Text(album)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(DS.Palette.onArtworkTertiary)
                    .lineLimit(DS.LineLimit.rowTitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var volumeRow: some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: "speaker.fill")
                .font(DS.Font.smallIcon)
                .accessibilityHidden(true)
            SystemVolumeSlider()
                .frame(height: DS.Size.volumeSlider)
            Image(systemName: "speaker.wave.3.fill")
                .font(DS.Font.smallIcon)
                .accessibilityHidden(true)
        }
        .foregroundStyle(DS.Palette.onArtworkSecondary)
    }

    private var secondaryControls: some View {
        HStack {
            QueueModeButtons()
            Spacer()
            SleepTimerMenu()
            Spacer()
            RoutePickerButton()
                .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            Spacer()
            Button {
                showsQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(DS.Font.controlIcon)
                    .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
            }
            .foregroundStyle(DS.Palette.onArtworkSecondary)
            .accessibilityLabel("Очередь")
        }
    }

    /// Свайп вниз по обложке или шапке закрывает плеер.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: DS.Gesture.dragMinimum)
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                if value.translation.height > DS.Gesture.dismissDistance
                    || value.predictedEndTranslation.height > DS.Gesture.dismissPredicted {
                    dismiss()
                }
                withAnimation(DS.Motion.animation(DS.Motion.standard, reduceMotion: reduceMotion)) {
                    dragOffset = 0
                }
            }
    }
}
