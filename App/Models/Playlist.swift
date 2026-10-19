import Foundation

struct Playlist: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var trackIDs: [UUID]
    let createdAt: Date

    init(id: UUID = UUID(), name: String, trackIDs: [UUID] = [], createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.trackIDs = trackIDs
        self.createdAt = createdAt
    }
}
