import SwiftUI

/// Полноэкранный плеер.
struct NowPlayingView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(\.dismiss) private var dismiss
    @State private var showsQueue = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let track = engine.currentTrack {
                content(track)
            } else {
                ContentUnavailableView("Ничего не играет", systemImage: "music.note")
                    .foregroundStyle(.white)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showsQueue) { QueueView() }
    }

    private func content(_ track: Track) -> some View {
        VStack(spacing: 24) {
            header
            Spacer(minLength: 8)
            ArtworkView(key: track.artworkKey, size: .large, cornerRadius: 16)
                .padding(.horizontal, 32)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
            Spacer(minLength: 8)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(track.artist ?? LibraryQuery.unknownArtist)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(.white)
            .accessibilityElement(children: .combine)

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
}
