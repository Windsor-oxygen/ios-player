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
            HStack(spacing: DS.Spacing.m) {
                ArtworkView(key: track.artworkKey, seed: track.title, cornerRadius: DS.Radius.m)
                    .frame(width: DS.Size.miniArtwork, height: DS.Size.miniArtwork)
                VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                    Text(track.title)
                        .font(DS.Font.miniTitle)
                        .lineLimit(DS.LineLimit.rowTitle)
                    Text(track.artist ?? LibraryQuery.unknownArtist)
                        .font(DS.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(DS.LineLimit.rowTitle)
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
                        .font(DS.Font.controlIcon)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                }
                .accessibilityLabel(engine.isPlaying ? "Пауза" : "Воспроизвести")
                .sensoryFeedback(.impact(weight: .medium), trigger: playTaps)

                Button {
                    nextTaps += 1
                    engine.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(DS.Font.controlIcon)
                        .frame(width: DS.Size.tapTarget, height: DS.Size.tapTarget)
                }
                .accessibilityLabel("Следующий трек")
                .sensoryFeedback(.impact(weight: .light), trigger: nextTaps)
            }
            .foregroundStyle(.primary)
            .buttonStyle(PressScaleButtonStyle())
            .padding(.leading, DS.Spacing.s)
            .padding(.trailing, DS.Spacing.xs)
            .padding(.vertical, DS.Spacing.s)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .overlay(alignment: .bottom) {
                MiniProgressBar()
                    .padding(.horizontal, DS.Spacing.l)
            }
            .dsShadow(DS.Shadow.miniPlayer)
            .matchedTransitionSource(id: Self.transitionID, in: namespace) { source in
                source.clipShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            }
            .contentShape(RoundedRectangle(cornerRadius: DS.Radius.xl, style: .continuous))
            .onTapGesture { open() }
            .gesture(
                // Свайп вверх по мини-плееру тоже открывает плеер.
                DragGesture(minimumDistance: DS.Gesture.dragMinimum).onEnded { value in
                    if value.translation.height < -DS.Gesture.openDistance { open() }
                }
            )
            .padding(.horizontal, DS.Spacing.s)
            .padding(.bottom, DS.Spacing.xs)
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
