import SwiftUI

/// Строка трека в списках. Лёгкая: только превью обложки 112 px и текст.
struct TrackRow: View {
    let track: Track
    /// Номер в альбоме вместо обложки.
    var showsTrackNumber = false

    var body: some View {
        HStack(spacing: 12) {
            if showsTrackNumber {
                Text(track.trackNumber.map(String.init) ?? "–")
                    .font(.body.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 24, alignment: .trailing)
            } else {
                ArtworkView(key: track.artworkKey)
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.body)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !track.isAvailable {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if track.duration > 0 {
                Text(TimeFormatter.string(from: track.duration))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .opacity(track.isAvailable ? 1 : 0.5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        if track.isMissing { return String(localized: "Файл не найден") }
        if track.isUnplayable { return String(localized: "Файл повреждён или не поддерживается") }
        let artist = track.artist ?? LibraryQuery.unknownArtist
        if let album = track.album { return "\(artist) — \(album)" }
        return artist
    }

    private var accessibilityText: String {
        var parts = [track.title, subtitle]
        if track.duration > 0 { parts.append(TimeFormatter.string(from: track.duration)) }
        return parts.joined(separator: ", ")
    }
}
