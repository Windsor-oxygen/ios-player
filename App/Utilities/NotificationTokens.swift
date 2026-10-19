import Foundation

/// Держит токены `NotificationCenter` и снимает их при освобождении.
/// Отдельный класс, потому что `deinit` у `@MainActor`-класса не может
/// трогать его изолированное состояние.
final class NotificationTokens {
    private var tokens: [NSObjectProtocol] = []

    func add(_ token: NSObjectProtocol) {
        tokens.append(token)
    }

    deinit {
        for token in tokens {
            NotificationCenter.default.removeObserver(token)
        }
    }
}
