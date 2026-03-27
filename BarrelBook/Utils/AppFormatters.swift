import Foundation

struct AppFormatters {

    /// Short "time ago" string, e.g. "2h ago", "Yesterday", "3d ago"
    static func formatDateShort(_ date: Date) -> String {
        let now = Date()
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes)m ago"
        } else if seconds < 86400 {
            let hours = Int(seconds / 3600)
            return "\(hours)h ago"
        } else if seconds < 172800 {
            return "Yesterday"
        } else {
            let days = Int(seconds / 86400)
            return "\(days)d ago"
        }
    }

    /// Formats a Double as a locale-aware currency string.
    static func formatCurrency(_ value: Double, maxFractionDigits: Int = 0) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = maxFractionDigits
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }
}
