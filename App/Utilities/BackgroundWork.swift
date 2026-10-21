import UIKit

/// Короткая фоновая задача iOS: даёт дописать данные на диск при уходе в фон.
@MainActor
final class BackgroundWork {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    /// Выполнить `work`, удерживая приложение активным. Если iOS отзовёт время
    /// раньше, задача завершается в обработчике — иначе система закроет приложение.
    static func run(_ name: String, _ work: @escaping @MainActor () async -> Void) {
        let task = BackgroundWork()
        task.identifier = UIApplication.shared.beginBackgroundTask(withName: name) {
            // Обработчик истечения времени iOS вызывает на main thread.
            MainActor.assumeIsolated { task.end() }
        }
        Task {
            await work()
            task.end()
        }
    }

    private func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
