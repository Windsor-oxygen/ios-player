import AVFoundation
import XCTest
@testable import Player

/// Повторный запуск трека без звуковых артефактов: кто обрабатывает конец трека,
/// когда перезапуск идёт перемоткой и в каком порядке вызывается плеер. Без звука.
@MainActor
final class PlaybackRestartTests: XCTestCase {
    /// Мок плеера: записывает вызовы, completion перемотки вызывает тест.
    private final class MockPlayer: SeekablePlayer {
        var log: [String] = []
        var completions: [@Sendable (Bool) -> Void] = []

        func pause() { log.append("pause") }
        func play() { log.append("play") }
        func seek(to time: CMTime, toleranceBefore: CMTime, toleranceAfter: CMTime,
                  completionHandler: @escaping @Sendable (Bool) -> Void) {
            XCTAssertEqual(toleranceBefore, .zero)
            XCTAssertEqual(toleranceAfter, .zero)
            log.append("seek \(time.seconds)")
            completions.append(completionHandler)
        }
    }

    /// Дать выполниться задачам, которые completion ставит на main actor.
    private func drainMainActor() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: - Пауза → seek(0) → play строго в completion

    func testRestartPausesSeeksAndPlaysOnlyInCompletion() async {
        let player = MockPlayer()
        let seeker = SeekSequencer()
        var finished = 0
        seeker.seek(player, to: 0, shouldResume: { true }, onFinish: { finished += 1 })

        XCTAssertEqual(player.log, ["pause", "seek 0.0"])
        XCTAssertTrue(seeker.isSeeking)
        await drainMainActor()
        XCTAssertEqual(player.log, ["pause", "seek 0.0"], "Звук не должен включиться до окончания перемотки")

        player.completions[0](true)
        await drainMainActor()
        XCTAssertEqual(player.log, ["pause", "seek 0.0", "play"])
        XCTAssertFalse(seeker.isSeeking)
        XCTAssertEqual(finished, 1)
    }

    func testSupersededSeekDoesNotPlay() async {
        let player = MockPlayer()
        let seeker = SeekSequencer()
        seeker.seek(player, to: 30, shouldResume: { true }, onFinish: {})
        seeker.seek(player, to: 0, shouldResume: { true }, onFinish: {})

        player.completions[0](false)
        await drainMainActor()
        XCTAssertFalse(player.log.contains("play"), "Устаревшая перемотка не включает звук")
        XCTAssertTrue(seeker.isSeeking)

        player.completions[1](true)
        await drainMainActor()
        XCTAssertEqual(player.log.filter { $0 == "play" }.count, 1)
    }

    func testPausedDuringSeekStaysPaused() async {
        let player = MockPlayer()
        let seeker = SeekSequencer()
        var wantsToPlay = true
        seeker.seek(player, to: 0, shouldResume: { wantsToPlay }, onFinish: {})
        wantsToPlay = false
        player.completions[0](true)
        await drainMainActor()
        XCTAssertFalse(player.log.contains("play"))
    }

    func testCancelledSeekDoesNotPlay() async {
        let player = MockPlayer()
        let seeker = SeekSequencer()
        seeker.seek(player, to: 0, shouldResume: { true }, onFinish: {})
        seeker.cancel()
        player.completions[0](true)
        await drainMainActor()
        XCTAssertFalse(player.log.contains("play"))
        XCTAssertFalse(seeker.isSeeking)
    }

    // MARK: - Конец трека: ровно один владелец перехода

    private func endAction(known: Bool = true, current: Bool = true, handled: Bool = false,
                           preloaded: Bool, stopAtEnd: Bool = false) -> TrackEndAction {
        TrackEndPolicy.action(isKnownItem: known, isCurrentItem: current, alreadyHandled: handled,
                              hasPreloadedSuccessor: preloaded, stopsAtEndOfTrack: stopAtEnd)
    }

    /// Repeat one, repeat all с одним треком и обычный переход с предзагрузкой:
    /// плеер переходит сам, мы ничего не пересоздаём (причина «двойного начала» в 1.1).
    func testPreloadedSuccessorIsLeftToPlayer() {
        XCTAssertEqual(endAction(preloaded: true), .followPlayer)
        // Даже если к моменту обработки элемент уже не текущий.
        XCTAssertEqual(endAction(current: false, preloaded: true), .followPlayer)
    }

    func testDuplicateEndNotificationIsIgnored() {
        XCTAssertEqual(endAction(handled: true, preloaded: false), .ignore)
        XCTAssertEqual(endAction(handled: true, preloaded: true), .ignore)
    }

    func testUnknownOrStaleItemIsIgnored() {
        XCTAssertEqual(endAction(known: false, preloaded: false), .ignore)
        XCTAssertEqual(endAction(current: false, preloaded: false), .ignore)
    }

    func testWithoutPreloadWeAdvanceOurselves() {
        XCTAssertEqual(endAction(preloaded: false), .advance)
        XCTAssertEqual(endAction(preloaded: false, stopAtEnd: true), .stopAfterTrack)
    }

    // MARK: - Когда перезапуск — перемоткой

    func testTappingLoadedTrackRestartsInPlace() {
        let id = UUID()
        // Играет или доиграл — тот же элемент, перемотка в 0.
        XCTAssertTrue(RestartPolicy.restartsInPlace(tapped: id, current: id, hasLoadedItem: true))
        XCTAssertFalse(RestartPolicy.restartsInPlace(tapped: id, current: UUID(), hasLoadedItem: true))
        XCTAssertFalse(RestartPolicy.restartsInPlace(tapped: id, current: id, hasLoadedItem: false))
    }

    func testPreviousRestartsAfterThresholdOrOnFirstTrack() {
        let current = UUID(), previous = UUID()
        // Позже 3 секунд — в начало трека.
        XCTAssertTrue(RestartPolicy.previousRestartsCurrent(elapsed: 10, threshold: 3,
                                                             previousEntry: previous, currentEntry: current))
        // В первые секунды — к предыдущему треку.
        XCTAssertFalse(RestartPolicy.previousRestartsCurrent(elapsed: 1, threshold: 3,
                                                              previousEntry: previous, currentEntry: current))
        // Первый трек без повтора: «предыдущий» — он же, значит перемотка, не пересоздание.
        XCTAssertTrue(RestartPolicy.previousRestartsCurrent(elapsed: 1, threshold: 3,
                                                             previousEntry: current, currentEntry: current))
        XCTAssertTrue(RestartPolicy.previousRestartsCurrent(elapsed: 1, threshold: 3,
                                                             previousEntry: nil, currentEntry: current))
    }

    // MARK: - Очередь: что играет после трека

    func testRepeatOneReplaysSameEntry() {
        var queue = PlaybackQueue()
        queue.replace(with: [UUID(), UUID()], startAt: 0, shuffled: false)
        queue.repeatMode = .one
        let current = queue.current
        XCTAssertEqual(queue.entryAfterCompletion, current)
        XCTAssertEqual(queue.advanceAfterCompletion(), current)
    }

    func testRepeatAllWithSingleTrackReplaysSameEntry() {
        var queue = PlaybackQueue()
        queue.replace(with: [UUID()], startAt: 0, shuffled: false)
        queue.repeatMode = .all
        let current = queue.current
        XCTAssertEqual(queue.entryAfterCompletion, current)
        XCTAssertEqual(queue.advanceAfterCompletion(), current)
    }

    func testEndOfQueueWithoutRepeatStopsAndRewinds() {
        var queue = PlaybackQueue()
        let ids = [UUID(), UUID()]
        queue.replace(with: ids, startAt: 1, shuffled: false)
        XCTAssertNil(queue.entryAfterCompletion)
        XCTAssertNil(queue.advanceAfterCompletion())
        queue.rewindToStart()
        XCTAssertEqual(queue.current?.trackID, ids[0])
    }

    func testPreviousOnFirstTrackWithoutRepeatStaysOnIt() {
        var queue = PlaybackQueue()
        queue.replace(with: [UUID(), UUID()], startAt: 0, shuffled: false)
        let current = queue.current
        XCTAssertEqual(queue.previous(), current)
    }
}
