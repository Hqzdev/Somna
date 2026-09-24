//
//  Presentation.swift
//  Somna
//
//  Formatting and colors for SomnaCore values on screen.
//

import SwiftUI
import Foundation

enum Fmt {
    /// "23:20" from minutes after midnight (wraps past 24 h).
    static func clock(_ minutes: Int) -> String {
        CoreFormat.clock(Double(minutes))
    }

    static func clock(_ minutes: Double) -> String {
        CoreFormat.clock(minutes)
    }

    /// "07:38" — a moment in the given zone.
    static func time(_ date: Date, _ timeZone: TimeZone = .current) -> String {
        clock(ClockTime.minutesOfDay(date, in: timeZone))
    }

    /// "7 ч 05 мин", "45 мин".
    static func duration(_ minutes: Int) -> String {
        CoreFormat.duration(minutes: Double(minutes))
    }

    static func duration(_ minutes: Double) -> String {
        CoreFormat.duration(minutes: minutes)
    }

    /// «+7 мин», «−18 мин».
    static func signed(_ minutes: Int) -> String {
        CoreFormat.signedMinutes(Double(minutes))
    }

    static func signed(_ minutes: Double) -> String {
        CoreFormat.signedMinutes(minutes)
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    static func number(_ value: Double, digits: Int = 0) -> String {
        let text = String(format: "%.\(digits)f", value)
        return digits > 0 ? text.replacingOccurrences(of: ".", with: ",") : text
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = SomnaCalendar.utcZone
        f.dateFormat = format
        return f
    }

    private static func noon(_ day: DayKey) -> Date {
        day.date(atMinutes: 12 * 60, in: SomnaCalendar.utcZone)
    }

    /// «Среда, 23 сентября».
    static func dayTitle(_ day: DayKey) -> String {
        formatter("EEEE, d MMMM").string(from: noon(day)).capitalizedFirst
    }

    /// «23 сентября».
    static func dayMonth(_ day: DayKey) -> String {
        formatter("d MMMM").string(from: noon(day))
    }

    /// «23».
    static func dayNumber(_ day: DayKey) -> String {
        "\(day.day)"
    }

    /// «ср».
    static func weekdayShort(_ day: DayKey) -> String {
        formatter("EEEEEE").string(from: noon(day))
    }

    static func isWeekend(_ day: DayKey) -> Bool {
        let weekday = SomnaCalendar.utc.component(.weekday, from: noon(day))
        return weekday == 1 || weekday == 7
    }

    /// «вторник → среда».
    static func nightSpan(_ day: DayKey) -> String {
        let f = formatter("EEEE")
        return "\(f.string(from: noon(day.adding(days: -1)))) → \(f.string(from: noon(day)))"
    }

    /// «сегодня в 07:52», «вчера», «23 сентября».
    static func relative(_ date: Date, now: Date = Date()) -> String {
        let today = DayKey(date: now, timeZone: .current)
        let day = DayKey(date: date, timeZone: .current)
        if day == today { return "сегодня в \(time(date))" }
        if day == today.adding(days: -1) { return "вчера в \(time(date))" }
        return dayMonth(day)
    }

    static func nights(_ n: Int) -> String {
        CoreFormat.nights(n)
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Sleep stages

extension SleepStage {
    var title: String {
        switch self {
        case .inBed: "В кровати"
        case .awake: "Бодрств."
        case .asleepUnspecified: "Сон"
        case .core: "Основной"
        case .deep: "Глубокий"
        case .rem: "REM"
        }
    }

    func color(_ p: Palette) -> Color {
        switch self {
        case .inBed: p.lineStrong
        case .awake: Brand.stageAwake
        case .rem: Brand.stageREM
        case .core: Brand.stageCore
        case .deep: p.stageDeep
        case .asleepUnspecified: Brand.lavenderMist
        }
    }
}

// MARK: - Signal states

extension SleepScore {
    var signal: SignalState {
        switch value {
        case 80...: .restore
        case 60..<80: .neutral
        default: .caution
        }
    }
}

enum Signal {
    static func recovery(_ value: Int) -> SignalState {
        switch value {
        case 75...: .restore
        case 55..<75: .caution
        default: .attention
        }
    }

    static func regularity(_ value: Double) -> SignalState {
        value >= 80 ? .restore : (value >= 60 ? .neutral : .caution)
    }
}

extension RegularityReport {
    /// «±24 мин».
    var spreadText: String { "±\(Int(combinedMAD.rounded())) мин" }
    var scoreText: String { "\(Int(score.rounded()))%" }
}

extension SleepBalance {
    /// Measured shortfall; extra sleep is shown separately.
    var text: String {
        guard hasCoverage else { return "—" }
        return shortfallMinutes < 1 ? "0 мин" : "−\(Fmt.duration(shortfallMinutes))"
    }
}

extension DataState {
    var isEmpty: Bool {
        if case .noData = self { return true }
        return false
    }

    var isCollecting: Bool {
        if case .collecting = self { return true }
        return false
    }
}
