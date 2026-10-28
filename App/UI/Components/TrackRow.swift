import SwiftUI

/// Строка трека в списках: миниатюра (или сгенерированная заглушка),
/// индикатор «сейчас играет», название, исполнитель, длительность.
struct TrackRow: View {
    let track: Track
    /// Номер в альбоме вместо обложки.
    var showsTrackNumber = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            leading
            VStack(alignment: .leading, spacing: DS.Spacing.xxs) {
                Text(track.title)
                    .font(DS.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(isLargeText ? DS.LineLimit.rowTitleLarge : DS.LineLimit.rowTitle)
                Text(subtitle)
                    .font(DS.Font.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(isLargeText ? DS.LineLimit.rowTitleLarge : DS.LineLimit.rowTitle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, DS.Spacing.xs)
        .opacity(track.isAvailable ? 1 : DS.Opacity.disabled)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .nowPlayingAccessibility(track.id)
    }

    @ViewBuilder
    private var leading: some View {
        if showsTrackNumber {
            ZStack {
                Text(track.trackNumber.map(String.init) ?? "–")
                    .font(DS.Font.trackNumber)
                    .foregroundStyle(.secondary)
                NowPlayingIndicator(trackID: track.id, placement: .inline)
                    .background(.background)
            }
            .frame(minWidth: DS.Size.trackNumberWidth, alignment: .center)
        } else {
            ArtworkView(key: track.displayArtworkKey, seed: track.id.uuidString)
                .overlay { NowPlayingIndicator(trackID: track.id) }
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.s, style: .continuous))
                .frame(width: DS.Size.rowArtwork, height: DS.Size.rowArtwork)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if !track.isAvailable {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DS.Palette.warning)
        } else if track.duration > 0, !isLargeText {
            Text(TimeFormatter.string(from: track.duration))
                .font(DS.Font.duration)
                .foregroundStyle(.secondary)
        }
    }

    private var isLargeText: Bool { dynamicTypeSize.isAccessibilitySize }

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
