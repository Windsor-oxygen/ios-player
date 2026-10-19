import Foundation

/// Текст алерта по итогам импорта.
enum ImportReportText {
    private static let maxListedFailures = 5

    static func title(_ report: ImportReport) -> String {
        let added = report.importedPaths.count
        let failed = report.failures.count
        if failed == 0 {
            return String(localized: "Добавлено песен: \(added)")
        }
        if added == 0 {
            return String(localized: "Не удалось добавить")
        }
        return String(localized: "Добавлено: \(added), с ошибкой: \(failed)")
    }

    static func message(_ report: ImportReport) -> String {
        var lines = report.failures.prefix(maxListedFailures).map { failure in
            "\(failure.fileName) — \(failure.error.errorDescription ?? "")"
        }
        let hidden = report.failures.count - maxListedFailures
        if hidden > 0 {
            lines.append(String(localized: "…и ещё \(hidden)"))
        }
        if report.setAsideCount > 0 {
            lines.append(String(localized: "Эти файлы не удалены: они лежат в «Файлы» → «На iPhone» → «Player» → «Не импортировано»."))
        }
        return lines.joined(separator: "\n")
    }
}
