import SwiftUI

/// Полноэкранный плеер.
struct NowPlayingView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsQueue = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            if let track = engine.currentTrack {
                content(track)
            } else {
                ContentUnavailableView("Ничего не играет", systemImage: "music.note")
                    .foregroundStyle(.white)
            }
        }
        // Фон через .background, чтобы растянутая обложка не влияла на раскладку.
        .background { DynamicBackground(artworkKey: engine.currentTrack?.artworkKey) }
        .overlay(alignment: .top) { MessageBanner(message: engine.message) }
        .offset(y: dragOffset)
        .environment(\.colorScheme, .dark)
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .sheet(isPresented: $showsQueue) { QueueView() }
    }

    private func content(_ track: Track) -> some View {
        VStack(spacing: 16) {
            header
            // Обложка занимает всё оставшееся место и остаётся квадратной.
            artwork(track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            titles(track)
            ScrubberView()
            TransportControls()
            volumeRow
            secondaryControls
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Свернуть плеер")
            Spacer()
            Capsule()
                .fill(.white.opacity(0.4))
                .frame(width: 40, height: 5)
                .accessibilityHidden(true)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .foregroundStyle(.white)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .gesture(dismissDrag)
    }

    private func artwork(_ track: Track) -> some View {
        ArtworkView(key: track.artworkKey, size: .large, cornerRadius: 20)
            .shadow(color: .black.opacity(engine.isPlaying ? 0.5 : 0.3),
                    radius: engine.isPlaying ? 32 : 16, y: engine.isPlaying ? 18 : 8)
            .scaleEffect(engine.isPlaying ? 1 : 0.84)
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.72), value: engine.isPlaying)
            .padding(8)
            .id(track.id)
            .transition(.opacity)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: track.id)
            .gesture(dismissDrag)
    }

    private func titles(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(track.title)
                .font(.title2.bold())
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text(track.artist ?? LibraryQuery.unknownArtist)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if let album = track.album {
                Text(album)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var volumeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .accessibilityHidden(true)
            SystemVolumeSlider()
                .frame(height: 32)
            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .accessibilityHidden(true)
        }
        .foregroundStyle(.white.opacity(0.7))
    }

    private var secondaryControls: some View {
        HStack {
            QueueModeButtons()
            Spacer()
            SleepTimerMenu()
            Spacer()
            RoutePickerButton()
                .frame(width: 44, height: 44)
            Spacer()
            Button {
                showsQueue = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("Очередь")
        }
    }

    /// Свайп вниз по обложке или шапке закрывает плеер.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                dragOffset = max(value.translation.height, 0)
            }
            .onEnded { value in
                if value.translation.height > 120 || value.predictedEndTranslation.height > 320 {
                    dismiss()
                }
                withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                    dragOffset = 0
                }
            }
    }
}

/// Всплывающее сообщение («Сыграет следующей», ошибки воспроизведения).
struct MessageBanner: View {
    let message: String?

    var body: some View {
        ZStack {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: message)
        .allowsHitTesting(false)
    }
}
