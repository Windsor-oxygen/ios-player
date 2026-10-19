import XCTest
@testable import Player

/// Детерминированный генератор для проверки shuffle.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class PlaybackQueueTests: XCTestCase {
    private let ids = (0..<5).map { _ in UUID() }

    private func queue(start: Int = 0, repeatMode: RepeatMode = .off) -> PlaybackQueue {
        var queue = PlaybackQueue()
        queue.replace(with: ids, startAt: start, shuffled: false)
        queue.repeatMode = repeatMode
        return queue
    }

    // MARK: Пустая очередь

    func testEmptyQueueIsSafe() {
        var queue = PlaybackQueue()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertNil(queue.current)
        XCTAssertNil(queue.next())
        XCTAssertNil(queue.previous())
        XCTAssertNil(queue.advanceAfterCompletion())
        XCTAssertNil(queue.entryAfterCompletion)
        queue.setShuffle(true)
        XCTAssertNil(queue.current)
        XCTAssertFalse(queue.removeTracks([UUID()]))
        queue.moveUpcoming(fromOffsets: [0], toOffset: 0)
        queue.removeUpcoming(atOffsets: [0])
        XCTAssertTrue(queue.isEmpty)
    }

    func testReplaceWithEmptyListClearsCurrent() {
        var queue = queue()
        queue.replace(with: [], startAt: 3, shuffled: true)
        XCTAssertNil(queue.current)
    }

    func testStartIndexIsClamped() {
        XCTAssertEqual(queue(start: 99).current?.trackID, ids[4])
        XCTAssertEqual(queue(start: -5).current?.trackID, ids[0])
    }

    // MARK: Один трек

    func testSingleTrack() {
        var queue = PlaybackQueue()
        queue.replace(with: [ids[0]], startAt: 0, shuffled: false)
        XCTAssertNil(queue.next())
        XCTAssertEqual(queue.previous()?.trackID, ids[0])
        XCTAssertNil(queue.advanceAfterCompletion())

        queue.repeatMode = .all
        XCTAssertEqual(queue.next()?.trackID, ids[0])
        XCTAssertEqual(queue.advanceAfterCompletion()?.trackID, ids[0])

        queue.repeatMode = .one
        XCTAssertEqual(queue.advanceAfterCompletion()?.trackID, ids[0])
    }

    // MARK: Next / previous / repeat

    func testNextWalksAndStopsAtEndWithoutRepeat() {
        var queue = queue()
        for index in 1..<5 {
            XCTAssertEqual(queue.next()?.trackID, ids[index])
        }
        XCTAssertNil(queue.next())
        XCTAssertEqual(queue.current?.trackID, ids[4], "Текущий трек не меняется в конце очереди")
    }

    func testRepeatAllWraps() {
        var queue = queue(start: 4, repeatMode: .all)
        XCTAssertEqual(queue.next()?.trackID, ids[0])
        XCTAssertEqual(queue.previous()?.trackID, ids[4])
        XCTAssertEqual(queue.advanceAfterCompletion()?.trackID, ids[0])
    }

    func testRepeatOneRepeatsOnCompletionButNextAdvances() {
        var queue = queue(start: 2, repeatMode: .one)
        XCTAssertEqual(queue.advanceAfterCompletion()?.trackID, ids[2])
        XCTAssertEqual(queue.entryAfterCompletion?.trackID, ids[2])
        XCTAssertEqual(queue.next()?.trackID, ids[3])
    }

    func testCompletionAtEndWithoutRepeatStops() {
        var queue = queue(start: 4)
        XCTAssertNil(queue.entryAfterCompletion)
        XCTAssertNil(queue.advanceAfterCompletion())
        queue.rewindToStart()
        XCTAssertEqual(queue.current?.trackID, ids[0])
    }

    func testPreviousOnFirstTrackStays() {
        var queue = queue()
        XCTAssertEqual(queue.previous()?.trackID, ids[0])
    }

    func testEntryAfterCompletionDoesNotMutate() {
        let queue = queue(start: 1)
        XCTAssertEqual(queue.entryAfterCompletion?.trackID, ids[2])
        XCTAssertEqual(queue.current?.trackID, ids[1])
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }

    // MARK: Shuffle

    func testShuffleKeepsCurrentFirstAndAllTracks() {
        var generator = SeededGenerator(state: 42)
        var queue = queue(start: 2)
        queue.setShuffle(true, using: &generator)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.current?.trackID, ids[2])
        XCTAssertEqual(queue.currentIndex, 0)
        XCTAssertEqual(Set(queue.entries.map(\.trackID)), Set(ids))
        XCTAssertEqual(queue.entries.count, ids.count)
    }

    func testUnshuffleRestoresOriginalOrderAndPosition() {
        var generator = SeededGenerator(state: 7)
        var queue = queue(start: 1)
        queue.setShuffle(true, using: &generator)
        _ = queue.next()
        let playing = queue.current
        queue.setShuffle(false)
        XCTAssertEqual(queue.entries.map(\.trackID), ids)
        XCTAssertEqual(queue.current, playing)
    }

    func testReplaceShuffledStartsWithChosenTrack() {
        var generator = SeededGenerator(state: 1)
        var queue = PlaybackQueue()
        queue.replace(with: ids, startAt: 3, shuffled: true, using: &generator)
        XCTAssertEqual(queue.current?.trackID, ids[3])
        XCTAssertTrue(queue.isShuffled)
    }

    // MARK: Editing

    func testPlayNextInsertsAfterCurrent() {
        var queue = queue(start: 1)
        let extra = UUID()
        queue.playNext([extra])
        XCTAssertEqual(queue.upcoming.first?.trackID, extra)
        XCTAssertEqual(queue.next()?.trackID, extra)
    }

    func testPlayNextSurvivesUnshuffle() {
        var generator = SeededGenerator(state: 3)
        var queue = queue(start: 1)
        queue.setShuffle(true, using: &generator)
        let extra = UUID()
        queue.playNext([extra])
        queue.setShuffle(false)
        XCTAssertEqual(queue.entries.map(\.trackID), [ids[0], ids[1], extra, ids[2], ids[3], ids[4]])
    }

    func testAppendToEmptyQueueSetsCurrent() {
        var queue = PlaybackQueue()
        queue.append([ids[0], ids[1]])
        XCTAssertEqual(queue.current?.trackID, ids[0])
        queue.playNext([ids[2]])
        XCTAssertEqual(queue.entries.map(\.trackID), [ids[0], ids[2], ids[1]])
    }

    func testSameTrackCanBeQueuedTwice() {
        var queue = queue(start: 0)
        queue.append([ids[0]])
        XCTAssertEqual(queue.entries.filter { $0.trackID == ids[0] }.count, 2)
        XCTAssertEqual(Set(queue.entries.map(\.id)).count, queue.entries.count)
    }

    func testMoveUpcoming() {
        var queue = queue(start: 1)
        // upcoming: 2, 3, 4 → переносим 4 в начало
        queue.moveUpcoming(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(queue.upcoming.map(\.trackID), [ids[4], ids[2], ids[3]])
        XCTAssertEqual(queue.current?.trackID, ids[1])
        XCTAssertEqual(queue.originalEntries.map(\.trackID), [ids[0], ids[1], ids[4], ids[2], ids[3]])
    }

    func testRemoveUpcoming() {
        var queue = queue(start: 1)
        queue.removeUpcoming(atOffsets: [0, 2])
        XCTAssertEqual(queue.upcoming.map(\.trackID), [ids[3]])
        XCTAssertEqual(queue.current?.trackID, ids[1])
    }

    func testJump() {
        var queue = queue()
        let target = queue.entries[3]
        XCTAssertEqual(queue.jump(to: target.id), target)
        XCTAssertEqual(queue.currentIndex, 3)
        XCTAssertNil(queue.jump(to: UUID()))
    }

    // MARK: Удалённые файлы

    func testRemovingCurrentTrackMovesToFollowing() {
        var queue = queue(start: 2)
        XCTAssertTrue(queue.removeTracks([ids[2]]))
        XCTAssertEqual(queue.current?.trackID, ids[3])
    }

    func testRemovingTracksBeforeCurrentKeepsCurrent() {
        var queue = queue(start: 3)
        XCTAssertFalse(queue.removeTracks([ids[0], ids[1]]))
        XCTAssertEqual(queue.current?.trackID, ids[3])
        XCTAssertEqual(queue.currentIndex, 1)
    }

    func testRemovingLastCurrentTrackClampsToEnd() {
        var queue = queue(start: 4)
        XCTAssertTrue(queue.removeTracks([ids[4]]))
        XCTAssertEqual(queue.current?.trackID, ids[3])
    }

    func testRemovingEverythingEmptiesQueue() {
        var queue = queue(start: 2)
        XCTAssertTrue(queue.removeTracks(Set(ids)))
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isEmpty)
    }

    func testClearKeepsRepeatMode() {
        var queue = queue(repeatMode: .all)
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.repeatMode, .all)
    }

    // MARK: Сохранение

    func testCodableRoundTrip() throws {
        var generator = SeededGenerator(state: 9)
        var queue = queue(start: 2, repeatMode: .one)
        queue.setShuffle(true, using: &generator)
        let data = try JSONEncoder().encode(queue)
        XCTAssertEqual(try JSONDecoder().decode(PlaybackQueue.self, from: data), queue)
    }

    func testLargeQueue() {
        let many = (0..<5000).map { _ in UUID() }
        var queue = PlaybackQueue()
        queue.replace(with: many, startAt: 2500, shuffled: true)
        XCTAssertEqual(queue.current?.trackID, many[2500])
        queue.setShuffle(false)
        XCTAssertEqual(queue.currentIndex, 2500)
    }
}
