import SwiftUI

/// Мини-плеер над таб-баром. Обложка — источник zoom-перехода в полноэкранный плеер.
struct MiniPlayerView: View {
    let namespace: Namespace.ID

    @Environment(PlaybackEngine.self) private var engine
    @Environment(AppPresenter.self) private var presenter
    @State private var playTaps = 0
    @State private var nextTaps = 0

    static let transitionID = "now-playing"

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
                .accessibilityAction { open() }

                Button {
                    playTaps += 1
                    engine.togglePlayPause()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(engine.isPlaying ? "Пауза" : "Воспроизвести")
                .sensoryFeedback(.impact(weight: .medium), trigger: playTaps)

                Button {
                    nextTaps += 1
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Следующий трек")
                .sensoryFeedback(.impact(weight: .light), trigger: nextTaps)
            }
            .buttonStyle(PressScaleButtonStyle())
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .bottom) {
                MiniProgressBar()
                    .padding(.horizontal, 16)
            }
            .matchedTransitionSource(id: Self.transitionID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .onTapGesture { open() }
            .gesture(
                // Свайп вверх по мини-плееру тоже открывает плеер.
                DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.height < -40 { open() }
                }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func open() {
        presenter.showsNowPlaying = true
    }
}

extension View {
    /// Место под мини-плеер внизу каждой вкладки (над таб-баром).
    func miniPlayerInset(namespace: Namespace.ID) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView(namespace: namespace)
        }
    }

    /// Zoom-переход из мини-плеера (iOS 18). При Reduce Motion — обычное появление.
    func nowPlayingTransition(namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        modifier(NowPlayingTransition(namespace: namespace, reduceMotion: reduceMotion))
    }
}

private struct NowPlayingTransition: ViewModifier {
    let namespace: Namespace.ID
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content.navigationTransition(.zoom(sourceID: MiniPlayerView.transitionID, in: namespace))
        }
    }
}
