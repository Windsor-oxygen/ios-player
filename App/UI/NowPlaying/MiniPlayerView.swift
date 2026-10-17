import SwiftUI

/// Мини-плеер над таб-баром.
struct MiniPlayerView: View {
    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppPresenter.self) private var presenter

    var body: some View {
        if let track = engine.currentTrack {
            HStack(spacing: 12) {
                ArtworkView(key: track.artworkKey, cornerRadius: 8)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(track.artist ?? LibraryQuery.unknownArtist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Открыть плеер")
                .accessibilityAction { presenter.showsNowPlaying = true }

                Button {
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(engine.isPlaying ? "Пауза" : "Воспроизвести")

                Button {
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Следующий трек")
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                MiniProgressBar()
                    .padding(.horizontal, 16)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture { presenter.showsNowPlaying = true }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
        }
    }
}

extension View {
    /// Место под мини-плеер внизу каждой вкладки (над таб-баром).
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView()
        }
    }
}
