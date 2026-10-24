import Foundation

enum TimeFormatting {
    static func separatorTitle(for date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "EEEE, MMMM d" : "MMMM d, yyyy", calendar: calendar).string(from: date)
    }

    static func time(_ date: Date, calendar: Calendar) -> String {
        formatter("h:mm a", calendar: calendar).string(from: date)
    }

    static func full(_ date: Date, calendar: Calendar) -> String {
        formatter("EEEE, MMMM d, yyyy 'at' h:mm a", calendar: calendar).string(from: date)
    }

    static func short(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return time(date, calendar: calendar) }
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return formatter(sameYear ? "MMM d" : "MMM d, yyyy", calendar: calendar).string(from: date)
    }

    static func relative(_ date: Date, now: Date, calendar: Calendar) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) hr ago" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday"
        }
        return short(date, now: now, calendar: calendar)
    }

    private static let cache = FormatterCache()

    private static func formatter(_ format: String, calendar: Calendar) -> DateFormatter {
        cache.formatter(format: format, calendar: calendar)
    }
}

final class FormatterCache: @unchecked Sendable {
    private let lock = NSLock()
    private var formatters: [String: DateFormatter] = [:]

    func formatter(format: String, calendar: Calendar) -> DateFormatter {
        let locale = calendar.locale ?? Locale(identifier: "en_US_POSIX")
        let key = "\(format)|\(calendar.timeZone.identifier)|\(locale.identifier)|\(calendar.identifier)"
        return lock.withLock {
            if let existing = formatters[key] { return existing }
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.dateFormat = format
            formatters[key] = formatter
            return formatter
        }
    }
}

enum BadgeText {
    static func count(_ value: Int) -> String {
        value > 99 ? "99+" : String(value)
    }
}

enum TypingText {
    static func text(for names: [String]) -> String? {
        switch names.count {
        case 0: return nil
        case 1: return "\(names[0]) is typing…"
        case 2: return "\(names[0]) and \(names[1]) are typing…"
        case 3: return "\(names[0]), \(names[1]) and \(names[2]) are typing…"
        default: return "\(names[0]), \(names[1]) and \(names.count - 2) others are typing…"
        }
    }
}

enum FileSizeText {
    static func text(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

enum Initials {
    static func of(_ name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        if letters.isEmpty { return String(name.prefix(1)).uppercased() }
        return String(letters).uppercased()
    }

    static func paletteIndex(for key: String, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let sum = key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff }
        return sum % count
    }
}
