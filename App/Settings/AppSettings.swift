import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: String(localized: "Тёмное")
        case .light: String(localized: "Светлое")
        case .system: String(localized: "Как в системе")
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// Что показывать на экране блокировки: iOS показывает либо
/// «предыдущий/следующий трек», либо «перемотку ±N секунд».
enum LockScreenControls: String, CaseIterable, Identifiable, Sendable {
    case tracks
    case skip

    var id: String { rawValue }
}

/// Пользовательские настройки (UserDefaults).
@MainActor
@Observable
final class AppSettings {
    static let skipIntervals: [Int] = [5, 10, 15, 30]

    var appearance: AppearanceMode {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Интервал кнопок перемотки, секунды.
    var skipInterval: Int {
        didSet { defaults.set(skipInterval, forKey: Keys.skipInterval) }
    }

    var lockScreenControls: LockScreenControls {
        didSet { defaults.set(lockScreenControls.rawValue, forKey: Keys.lockScreenControls) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let appearance = "settings.appearance"
        static let skipInterval = "settings.skipInterval"
        static let lockScreenControls = "settings.lockScreenControls"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearance = defaults.string(forKey: Keys.appearance).flatMap(AppearanceMode.init(rawValue:)) ?? .dark
        let storedInterval = defaults.integer(forKey: Keys.skipInterval)
        skipInterval = Self.skipIntervals.contains(storedInterval) ? storedInterval : 15
        lockScreenControls = defaults.string(forKey: Keys.lockScreenControls)
            .flatMap(LockScreenControls.init(rawValue:)) ?? .tracks
    }
}
