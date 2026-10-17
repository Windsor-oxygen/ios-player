import Foundation

enum TimeFormatter {
    /// 0 → «0:00», 65 → «1:05», 3725 → «1:02:05». NaN, ∞ и отрицательные → «0:00».
    static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}
