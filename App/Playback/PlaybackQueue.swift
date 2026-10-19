import Foundation

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one

    /// Следующий режим по нажатию кнопки: off → all → one → off.
    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Элемент очереди. Свой `id`, потому что один трек может стоять в очереди дважды.
struct QueueEntry: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let trackID: UUID

    init(trackID: UUID, id: UUID = UUID()) {
        self.id = id
        self.trackID = trackID
    }
}

/// Логика очереди без AVFoundation: shuffle, repeat, next/previous,
/// вставка, перестановка, удаление. Покрыта unit-тестами.
struct PlaybackQueue: Codable, Equatable, Sendable {
    /// Порядок воспроизведения (перемешанный, если включён shuffle).
    private(set) var entries: [QueueEntry] = []
    /// Исходный порядок — к нему возвращаемся при выключении shuffle.
    private(set) var originalEntries: [QueueEntry] = []
    private(set) var currentIndex: Int?
    private(set) var isShuffled = false
    var repeatMode: RepeatMode = .off

    var isEmpty: Bool { entries.isEmpty }

    var current: QueueEntry? {
        guard let currentIndex, entries.indices.contains(currentIndex) else { return nil }
        return entries[currentIndex]
    }

    /// Что будет играть после текущего.
    var upcoming: ArraySlice<QueueEntry> {
        guard let currentIndex, currentIndex < entries.count else { return entries[...] }
        return entries[(currentIndex + 1)...]
    }

    // MARK: - Replace

    /// Новая очередь, начиная с трека `startIndex` исходного списка.
    mutating func replace(with trackIDs: [UUID], startAt startIndex: Int, shuffled: Bool) {
        var generator = SystemRandomNumberGenerator()
        replace(with: trackIDs, startAt: startIndex, shuffled: shuffled, using: &generator)
    }

    mutating func replace(with trackIDs: [UUID], startAt startIndex: Int, shuffled: Bool,
                          using generator: inout some RandomNumberGenerator) {
        originalEntries = trackIDs.map { QueueEntry(trackID: $0) }
        entries = originalEntries
        isShuffled = false
        guard !entries.isEmpty else {
            currentIndex = nil
            return
        }
        currentIndex = min(max(startIndex, 0), entries.count - 1)
        if shuffled {
            setShuffle(true, using: &generator)
        }
    }

    // MARK: - Shuffle

    mutating func setShuffle(_ enabled: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffle(enabled, using: &generator)
    }

    mutating func setShuffle(_ enabled: Bool, using generator: inout some RandomNumberGenerator) {
        guard enabled != isShuffled else { return }
        isShuffled = enabled
        let current = self.current
        if enabled {
            // Текущий трек остаётся первым, остальные — в случайном порядке.
            var rest = entries
            if let currentIndex { rest.remove(at: currentIndex) }
            rest.shuffle(using: &generator)
            if let current {
                entries = [current] + rest
                currentIndex = 0
            } else {
                entries = rest
            }
        } else {
            entries = originalEntries
            currentIndex = current.flatMap { entry in entries.firstIndex { $0.id == entry.id } }
                ?? (entries.isEmpty ? nil : 0)
        }
    }

    // MARK: - Navigation

    /// Трек закончился сам. `nil` — очередь закончилась, воспроизведение останавливается.
    mutating func advanceAfterCompletion() -> QueueEntry? {
        guard let currentIndex, !entries.isEmpty else { return nil }
        if repeatMode == .one { return current }
        if currentIndex + 1 < entries.count {
            self.currentIndex = currentIndex + 1
            return current
        }
        if repeatMode == .all {
            self.currentIndex = 0
            return current
        }
        return nil
    }

    /// Что сыграет после текущего трека без участия пользователя (для предзагрузки).
    var entryAfterCompletion: QueueEntry? {
        var copy = self
        return copy.advanceAfterCompletion()
    }

    /// Кнопка «Вперёд». Repeat-one не мешает перейти к следующему.
    /// `nil` — дальше ничего нет (repeat off на последнем треке).
    mutating func next() -> QueueEntry? {
        guard let currentIndex, !entries.isEmpty else { return nil }
        if currentIndex + 1 < entries.count {
            self.currentIndex = currentIndex + 1
            return current
        }
        if repeatMode != .off {
            self.currentIndex = 0
            return current
        }
        return nil
    }

    /// Кнопка «Назад» (перемотку в начало при позиции > 3 с решает движок).
    /// На первом треке без repeat остаётся на нём же.
    mutating func previous() -> QueueEntry? {
        guard let currentIndex, !entries.isEmpty else { return nil }
        if currentIndex > 0 {
            self.currentIndex = currentIndex - 1
        } else if repeatMode != .off {
            self.currentIndex = entries.count - 1
        }
        return current
    }

    /// Возврат к началу очереди (после её окончания).
    mutating func rewindToStart() {
        currentIndex = entries.isEmpty ? nil : 0
    }

    /// Переход к элементу очереди по нажатию в списке.
    @discardableResult
    mutating func jump(to entryID: UUID) -> QueueEntry? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        currentIndex = index
        return current
    }

    // MARK: - Editing

    /// «Играть следующим».
    mutating func playNext(_ trackIDs: [UUID]) {
        let new = trackIDs.map { QueueEntry(trackID: $0) }
        guard !new.isEmpty else { return }
        guard let current else {
            appendToEmpty(new)
            return
        }
        if let index = currentIndex {
            entries.insert(contentsOf: new, at: index + 1)
        }
        let originalIndex = originalEntries.firstIndex { $0.id == current.id } ?? (originalEntries.count - 1)
        originalEntries.insert(contentsOf: new, at: originalIndex + 1)
    }

    /// «Добавить в очередь» (в конец).
    mutating func append(_ trackIDs: [UUID]) {
        let new = trackIDs.map { QueueEntry(trackID: $0) }
        guard !new.isEmpty else { return }
        guard current != nil else {
            appendToEmpty(new)
            return
        }
        entries.append(contentsOf: new)
        originalEntries.append(contentsOf: new)
    }

    private mutating func appendToEmpty(_ new: [QueueEntry]) {
        entries.append(contentsOf: new)
        originalEntries.append(contentsOf: new)
        if currentIndex == nil { currentIndex = entries.count - new.count }
    }

    /// Перестановка внутри «Далее» (индексы относительно `upcoming`).
    mutating func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        let base = (currentIndex ?? -1) + 1
        guard base <= entries.count else { return }
        var tail = Array(entries[base...])
        // Array.move падает на индексах вне диапазона — отбрасываем их.
        let valid = IndexSet(source.filter { tail.indices.contains($0) })
        guard !valid.isEmpty else { return }
        tail.move(fromOffsets: valid, toOffset: min(max(destination, 0), tail.count))
        entries.replaceSubrange(base..., with: tail)
        if !isShuffled { originalEntries = entries }
    }

    /// Удаление из «Далее» (индексы относительно `upcoming`).
    mutating func removeUpcoming(atOffsets offsets: IndexSet) {
        let base = (currentIndex ?? -1) + 1
        let ids = Set(offsets.compactMap { entries.indices.contains(base + $0) ? entries[base + $0].id : nil })
        entries.removeAll { ids.contains($0.id) }
        originalEntries.removeAll { ids.contains($0.id) }
    }

    /// Удалить все вхождения треков (файлы удалены из библиотеки).
    /// Возвращает `true`, если был удалён текущий трек.
    @discardableResult
    mutating func removeTracks(_ trackIDs: Set<UUID>) -> Bool {
        guard !trackIDs.isEmpty else { return false }
        let currentRemoved = current.map { trackIDs.contains($0.trackID) } ?? false
        let oldIndex = currentIndex ?? 0
        let removedBefore = entries.prefix(oldIndex).filter { trackIDs.contains($0.trackID) }.count
        entries.removeAll { trackIDs.contains($0.trackID) }
        originalEntries.removeAll { trackIDs.contains($0.trackID) }
        if entries.isEmpty {
            currentIndex = nil
        } else if currentIndex != nil {
            // Текущим становится следующий за удалённым (или последний).
            currentIndex = min(oldIndex - removedBefore, entries.count - 1)
        }
        return currentRemoved
    }

    mutating func clear() {
        self = PlaybackQueue(repeatMode: repeatMode)
    }

    private init(repeatMode: RepeatMode) {
        self.repeatMode = repeatMode
    }

    init() {}
}
