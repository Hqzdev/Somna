//
//  CoreTime.swift
//  SomnaCore
//
//  Calendar helpers. A night is keyed by the local calendar day of waking up
//  (in the time zone where the person woke), so travel, midnight and
//  daylight-saving changes are handled with local clock time, not UTC.
//
//  SomnaCore is pure Swift + Foundation: no SwiftUI, no HealthKit. The same
//  files build into the iPhone app and the SomnaCore package (tests, a future
//  Apple Watch app).
//

import Foundation

/// Local calendar day, e.g. 2026-09-23.
nonisolated struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// The local day of `date` in `timeZone`.
    init(date: Date, timeZone: TimeZone) {
        let c = SomnaCalendar.gregorian(timeZone).dateComponents([.year, .month, .day], from: date)
        self.init(year: c.year ?? 1970, month: c.month ?? 1, day: c.day ?? 1)
    }

    /// Parses "yyyy-MM-dd".
    init?(string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Local midnight that starts this day.
    func startDate(in timeZone: TimeZone) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 0
        return SomnaCalendar.gregorian(timeZone).date(from: c) ?? Date(timeIntervalSince1970: 0)
    }

    /// A local clock time on this day, e.g. 23:20 → minutes = 1400.
    /// Minutes beyond 24 h roll into the next day.
    func date(atMinutes minutes: Int, in timeZone: TimeZone) -> Date {
        let extraDays = Int((Double(minutes) / 1440).rounded(.down))
        let m = minutes - extraDays * 1440
        var c = DateComponents()
        let base = adding(days: extraDays)
        c.year = base.year
        c.month = base.month
        c.day = base.day
        c.hour = m / 60
        c.minute = m % 60
        return SomnaCalendar.gregorian(timeZone).date(from: c) ?? startDate(in: timeZone)
    }

    func adding(days: Int) -> DayKey {
        let utc = SomnaCalendar.utc
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        guard let d = utc.date(from: c), let moved = utc.date(byAdding: .day, value: days, to: d) else { return self }
        return DayKey(date: moved, timeZone: SomnaCalendar.utcZone)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    func days(to other: DayKey) -> Int {
        let utc = SomnaCalendar.utc
        var a = DateComponents()
        a.year = year; a.month = month; a.day = day; a.hour = 12
        var b = DateComponents()
        b.year = other.year; b.month = other.month; b.day = other.day; b.hour = 12
        guard let da = utc.date(from: a), let db = utc.date(from: b) else { return 0 }
        return utc.dateComponents([.day], from: da, to: db).day ?? 0
    }

    // Codable as "yyyy-MM-dd".
    init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let key = DayKey(string: s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad day key \(s)"))
        }
        self = key
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

nonisolated enum SomnaCalendar {
    static let utcZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!

    static var utc: Calendar { gregorian(utcZone) }

    static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = Locale(identifier: "ru_RU")
        cal.firstWeekday = 2
        return cal
    }

    static func zone(_ identifier: String?, fallback: TimeZone) -> TimeZone {
        guard let identifier, let tz = TimeZone(identifier: identifier) else { return fallback }
        return tz
    }
}

/// Local clock positions on continuous scales, so that 23:50 and 00:10 are
/// 20 minutes apart, not 23 h 40 min.
nonisolated enum ClockTime {
    /// Minutes after local midnight (0 ..< 1440).
    static func minutesOfDay(_ date: Date, in timeZone: TimeZone) -> Double {
        let c = SomnaCalendar.gregorian(timeZone).dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// Bedtime on a noon-to-noon scale: minutes after 12:00.
    /// 22:00 → 600, 23:30 → 690, 00:30 → 750, 03:00 → 900.
    static func bedtimeScale(_ date: Date, in timeZone: TimeZone) -> Double {
        let m = minutesOfDay(date, in: timeZone)
        return m >= 720 ? m - 720 : m + 720
    }

    /// Wake time as minutes after local midnight (06:45 → 405).
    static func wakeScale(_ date: Date, in timeZone: TimeZone) -> Double {
        minutesOfDay(date, in: timeZone)
    }

    /// Converts a bedtime-scale value back to minutes of day (0 ..< 1440).
    static func minutesOfDay(fromBedtimeScale value: Double) -> Double {
        var m = (value + 720).truncatingRemainder(dividingBy: 1440)
        if m < 0 { m += 1440 }
        return m
    }
}

/// Russian formatting used by explanations built in the core.
nonisolated enum CoreFormat {
    /// "23:20" from minutes of day (wraps around midnight).
    static func clock(_ minutesOfDay: Double) -> String {
        var m = Int(minutesOfDay.rounded()) % 1440
        if m < 0 { m += 1440 }
        return String(format: "%02d:%02d", m / 60, m % 60)
    }

    /// "7 ч 05 мин", "45 мин".
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        let sign = total < 0 ? "−" : ""
        let a = abs(total)
        if a < 60 { return "\(sign)\(a) мин" }
        return "\(sign)\(a / 60) ч \(String(format: "%02d", a % 60)) мин"
    }

    /// "+12 мин" / "−8 мин" / "0 мин".
    static func signedMinutes(_ minutes: Double) -> String {
        let v = Int(minutes.rounded())
        if v > 0 { return "+\(v) мин" }
        if v < 0 { return "−\(-v) мин" }
        return "0 мин"
    }

    /// Russian plural: 1 ночь, 2 ночи, 5 ночей.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10
        let n100 = n % 100
        if n10 == 1 && n100 != 11 { return one }
        if (2...4).contains(n10) && !(12...14).contains(n100) { return few }
        return many
    }

    static func nights(_ n: Int) -> String {
        "\(n) \(plural(n, "ночь", "ночи", "ночей"))"
    }
}
