import MediaPlayer
import UIKit

/// Информация на экране блокировки и в Пункте управления.
/// Обновляется только по событиям (смена трека, пауза, seek, rate), не по таймеру:
/// iOS сама продвигает ползунок по elapsed time и rate.
@MainActor
final class NowPlayingController {
    struct State {
        let track: Track
        let elapsed: TimeInterval
        let duration: TimeInterval
        let isPlaying: Bool
        let queueIndex: Int?
        let queueCount: Int
    }

    private let center = MPNowPlayingInfoCenter.default()
    private var artwork: MPMediaItemArtwork?
    private var artworkTrackID: UUID?

    func update(_ state: State) {
        if artworkTrackID != state.track.id {
            artwork = nil
            artworkTrackID = nil
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: state.track.title,
            MPMediaItemPropertyPlaybackDuration: max(state.duration, 0),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(state.elapsed, 0),
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: state.queueCount,
        ]
        if let artist = state.track.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = state.track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let index = state.queueIndex { info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = index }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        center.nowPlayingInfo = info
    }

    /// Обложка приходит асинхронно — дописываем её в уже опубликованную информацию.
    func setArtwork(_ image: UIImage, for trackID: UUID) {
        let artwork = Self.makeArtwork(image)
        self.artwork = artwork
        artworkTrackID = trackID
        guard var info = center.nowPlayingInfo else { return }
        info[MPMediaItemPropertyArtwork] = artwork
        center.nowPlayingInfo = info
    }

    func clear() {
        artwork = nil
        artworkTrackID = nil
        center.nowPlayingInfo = nil
    }

    /// Замыкание MPMediaItemArtwork система вызывает на произвольном потоке,
    /// поэтому создаём его вне main actor — иначе оно унаследует изоляцию.
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
}
