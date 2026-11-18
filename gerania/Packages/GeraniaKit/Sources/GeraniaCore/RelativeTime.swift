import Foundation

/// Human readable distance to a moment in time.
public enum RelativeTime {
    /// Short description of the moment, for example «5 мин» or «вчера».
    public static func string(for date: Date, now: Date, locale: Locale = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 {
            return "сейчас"
        }
        if seconds < 3600 {
            return "\(Int(seconds / 60)) мин"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600)) ч"
        }
        let days = Int(seconds / 86400)
        if days == 1 {
            return "вчера"
        }
        if days < 7 {
            return "\(days) дн"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
