import Observation
import UIKit

/// Вариант иконки приложения.
struct AppIconOption: Identifiable, Hashable, Sendable {
    /// Имя набора в asset catalog; `nil` — основная иконка.
    let iconName: String?
    let title: String

    var id: String { iconName ?? "AppIcon" }
    /// Картинка для сетки выбора (`IconPreview-*.imageset`).
    var previewName: String { "IconPreview-\(id)" }
}

/// Смена иконки приложения. Выбор хранит сама iOS (`alternateIconName`),
/// поэтому приложение ничего не сохраняет. Системное уведомление о смене
/// iOS показывает сама — скрывать его нельзя и не нужно.
@MainActor
@Observable
final class AppIconController {
    static let options: [AppIconOption] = [
        AppIconOption(iconName: nil, title: String(localized: "Аврора")),
        AppIconOption(iconName: "AppIcon-Sunset", title: String(localized: "Закат")),
        AppIconOption(iconName: "AppIcon-Ocean", title: String(localized: "Океан")),
        AppIconOption(iconName: "AppIcon-Mint", title: String(localized: "Мята")),
        AppIconOption(iconName: "AppIcon-Graphite", title: String(localized: "Графит")),
        AppIconOption(iconName: "AppIcon-Paper", title: String(localized: "Бумага")),
        AppIconOption(iconName: "AppIcon-Neon", title: String(localized: "Неон")),
    ]

    private(set) var currentIconName: String?
    private(set) var isChanging = false
    private(set) var supportsAlternateIcons = true
    /// Ошибка для алерта; UI обнуляет после показа.
    var errorMessage: String?

    var current: AppIconOption {
        Self.options.first { $0.iconName == currentIconName } ?? Self.options[0]
    }

    /// Прочитать текущее состояние у системы (при открытии экрана).
    func refresh() {
        let application = UIApplication.shared
        supportsAlternateIcons = application.supportsAlternateIcons
        currentIconName = application.alternateIconName
    }

    /// `true` — иконка сменилась.
    func select(_ option: AppIconOption) async -> Bool {
        guard option.iconName != currentIconName, !isChanging else { return false }
        let application = UIApplication.shared
        guard application.supportsAlternateIcons else {
            supportsAlternateIcons = false
            errorMessage = String(localized: "Эта версия iOS не позволяет менять иконку приложения.")
            return false
        }
        isChanging = true
        defer { isChanging = false }
        do {
            try await application.setAlternateIconName(option.iconName)
            currentIconName = option.iconName
            return true
        } catch {
            Log.storage.error("Не удалось сменить иконку: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "Не удалось сменить иконку. Попробуйте ещё раз. (\(error.localizedDescription))")
            currentIconName = application.alternateIconName
            return false
        }
    }
}
