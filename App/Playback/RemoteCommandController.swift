import MediaPlayer

/// Кнопки экрана блокировки, Пункта управления, гарнитур и AirPods.
@MainActor
final class RemoteCommandController {
    typealias Action = @MainActor @Sendable () -> MPRemoteCommandHandlerStatus

    struct Handlers {
        let play: Action
        let pause: Action
        let togglePlayPause: Action
        let next: Action
        let previous: Action
        let skipForward: Action
        let skipBackward: Action
        let seek: @MainActor @Sendable (TimeInterval) -> MPRemoteCommandHandlerStatus
    }

    private let center = MPRemoteCommandCenter.shared()
    private let handlers: Handlers
    private let targets = RemoteTargets()

    init(handlers: Handlers) {
        self.handlers = handlers
        targets.add(center.playCommand, Self.handler(handlers.play))
        targets.add(center.pauseCommand, Self.handler(handlers.pause))
        targets.add(center.togglePlayPauseCommand, Self.handler(handlers.togglePlayPause))
        targets.add(center.changePlaybackPositionCommand, Self.seekHandler(handlers.seek))
        for command in [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.changePlaybackPositionCommand] {
            command.isEnabled = true
        }
        // Не используемые нами команды явно выключаем.
        for command in [center.stopCommand, center.changeRepeatModeCommand, center.changeShuffleModeCommand,
                        center.likeCommand, center.dislikeCommand, center.bookmarkCommand,
                        center.seekForwardCommand, center.seekBackwardCommand, center.changePlaybackRateCommand] {
            command.isEnabled = false
        }
    }

    /// iOS показывает на экране блокировки либо треки, либо перемотку —
    /// включаем одну пару команд и снимаем обработчики с другой.
    func configure(mode: LockScreenControls, skipInterval: Int) {
        let trackCommands = [center.nextTrackCommand, center.previousTrackCommand]
        let skipCommands: [MPRemoteCommand] = [center.skipForwardCommand, center.skipBackwardCommand]
        for command in trackCommands + skipCommands {
            targets.remove(command)
        }
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipInterval)]

        switch mode {
        case .tracks:
            targets.add(center.nextTrackCommand, Self.handler(handlers.next))
            targets.add(center.previousTrackCommand, Self.handler(handlers.previous))
        case .skip:
            targets.add(center.skipForwardCommand, Self.handler(handlers.skipForward))
            targets.add(center.skipBackwardCommand, Self.handler(handlers.skipBackward))
        }
        for command in trackCommands { command.isEnabled = mode == .tracks }
        for command in skipCommands { command.isEnabled = mode == .skip }
    }

    /// Снять все обработчики (сброс медиасервисов, завершение).
    func invalidate() {
        targets.removeAll()
    }

    // MARK: - Handlers

    /// Обработчики создаются вне main actor: система вызывает их на main thread,
    /// но формально без гарантий, поэтому проверяем поток явно и не падаем.
    private nonisolated static func handler(_ action: @escaping Action) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { _ in perform(action) }
    }

    private nonisolated static func seekHandler(
        _ action: @escaping @MainActor @Sendable (TimeInterval) -> MPRemoteCommandHandlerStatus
    ) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            return perform { action(position) }
        }
    }

    private nonisolated static func perform(_ action: @escaping Action) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { action() }
        }
        Task { @MainActor in _ = action() }
        return .success
    }
}

/// Токены `addTarget`. Снимаются при освобождении — отдельный класс,
/// потому что `deinit` `@MainActor`-класса не может трогать его состояние.
private final class RemoteTargets {
    private var entries: [(command: MPRemoteCommand, token: Any)] = []

    func add(_ command: MPRemoteCommand, _ handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        entries.append((command, command.addTarget(handler: handler)))
    }

    func remove(_ command: MPRemoteCommand) {
        for entry in entries where entry.command === command {
            command.removeTarget(entry.token)
        }
        entries.removeAll { $0.command === command }
    }

    func removeAll() {
        for entry in entries {
            entry.command.removeTarget(entry.token)
        }
        entries.removeAll()
    }

    deinit {
        removeAll()
    }
}
