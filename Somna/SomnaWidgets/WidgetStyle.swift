//
//  WidgetStyle.swift
//  SomnaWidgets
//
//  Tokens mirrored from DesignSystem/Theme.swift (the extension does not
//  compile the app's design system), fonts, formatting and gallery data.
//

import SwiftUI
import WidgetKit

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Palette

struct WPalette {
    var top: Color
    var bottom: Color
    var fg: Color
    var fg2: Color
    var fg3: Color
    var accent: Color
    var soft: Color
    var line: Color
    var stageDeep: Color
    var isDark: Bool

    /// Same hours as the app: dawn 05–15, sunset 15–18, dusk 18–21, night 21–05.
    static func at(hour: Int) -> WPalette {
        switch hour {
        case 5..<15: .dawn
        case 15..<18: .sunset
        case 18..<21: .dusk
        default: .night
        }
    }

    static let dawn = WPalette(top: Color(hex: 0xFFE1CC), bottom: Color(hex: 0xFBF6F1),
                               fg: Color(hex: 0x151581), fg2: Color(hex: 0x151581, alpha: 0.66),
                               fg3: Color(hex: 0x6868AA), accent: Color(hex: 0x5465FF),
                               soft: Color(hex: 0x5465FF, alpha: 0.10), line: Color(hex: 0x151581, alpha: 0.10),
                               stageDeep: Color(hex: 0x151581), isDark: false)

    static let sunset = WPalette(top: Color(hex: 0xF3D0C4), bottom: Color(hex: 0xEEEBF3),
                                 fg: Color(hex: 0x151581), fg2: Color(hex: 0x151581, alpha: 0.68),
                                 fg3: Color(hex: 0x6464A8), accent: Color(hex: 0x5465FF),
                                 soft: Color(hex: 0x5465FF, alpha: 0.12), line: Color(hex: 0x151581, alpha: 0.12),
                                 stageDeep: Color(hex: 0x151581), isDark: false)

    static let dusk = WPalette(top: Color(hex: 0x38378A), bottom: Color(hex: 0x232266),
                               fg: Color(hex: 0xF6F6FA), fg2: Color(hex: 0xC5C5E6),
                               fg3: Color(hex: 0x9C9CCB), accent: Color(hex: 0x9AA4FF),
                               soft: Color(hex: 0x9AA4FF, alpha: 0.16), line: Color(hex: 0xFFFFFF, alpha: 0.12),
                               stageDeep: Color(hex: 0xC9CCFF), isDark: true)

    static let night = WPalette(top: Color(hex: 0x1C1C6B), bottom: Color(hex: 0x0B0B3B),
                                fg: Color(hex: 0xF6F6FA), fg2: Color(hex: 0xA1A1CD),
                                fg3: Color(hex: 0x8080BA), accent: Color(hex: 0x8A96FF),
                                soft: Color(hex: 0x8A96FF, alpha: 0.15), line: Color(hex: 0xFFFFFF, alpha: 0.12),
                                stageDeep: Color(hex: 0xC9CCFF), isDark: true)
}

enum WBrand {
    static let restore = Color(hex: 0x00BB76)
    static let caution = Color(hex: 0xFF85B1)
    static let stageAwake = Color(hex: 0xFF85B1)
    static let stageREM = Color(hex: 0x20A2E3)
    static let stageCore = Color(hex: 0x5465FF)
    /// Brand orb — decorative only.
    static let orb = LinearGradient(colors: [Color(hex: 0x8A96FF), Color(hex: 0xFF8F66), Color(hex: 0xFFC27A)],
                                    startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Fonts (bundled in the extension, listed in UIAppFonts)

enum WFont {
    /// Inter Tight Regular: hierarchy comes from size, never from weight.
    static func display(_ size: CGFloat) -> Font {
        .custom("InterTight-Regular", fixedSize: size)
    }

    static func body(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "Inter-Medium"
        case .semibold, .bold, .heavy, .black: name = "Inter-SemiBold"
        default: name = "Inter-Regular"
        }
        return .custom(name, fixedSize: size)
    }
}

// MARK: - Formatting

enum WFormat {
    private static let locale = Locale(identifier: "ru_RU")

    private static func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = timeZone
        f.dateFormat = format
        return f
    }

    /// "23:20"
    static func clock(_ date: Date, _ timeZone: TimeZone) -> String {
        formatter("HH:mm", timeZone).string(from: date)
    }

    /// "7 ч 05 мин", "45 мин" — same as CoreFormat.duration.
    static func duration(_ minutes: Int) -> String {
        let sign = minutes < 0 ? "−" : ""
        let a = abs(minutes)
        if a < 60 { return "\(sign)\(a) мин" }
        return "\(sign)\(a / 60) ч \(String(format: "%02d", a % 60)) мин"
    }

    /// "7:14"
    static func hoursMinutes(_ minutes: Int) -> String {
        "\(minutes / 60):\(String(format: "%02d", minutes % 60))"
    }

    /// "ср"
    static func weekdayShort(_ date: Date, _ timeZone: TimeZone) -> String {
        formatter("EE", timeZone).string(from: date).lowercased()
    }

    /// "Среда, 23 сентября"
    static func longDate(_ date: Date, _ timeZone: TimeZone) -> String {
        let text = formatter("EEEE, d MMMM", timeZone).string(from: date)
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// "23 сент."
    static func shortDate(_ date: Date, _ timeZone: TimeZone) -> String {
        formatter("d MMM", timeZone).string(from: date)
    }

    /// "yyyy-MM-dd" of a local midnight.
    static func dayKey(_ date: Date, _ timeZone: TimeZone) -> String {
        formatter("yyyy-MM-dd", timeZone).string(from: date)
    }
}

// MARK: - Gallery data (canonical example from the design: night 22→23 September)

extension WidgetSnapshot {
    static var preview: WidgetSnapshot {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let today = calendar.startOfDay(for: Date())
        let start = today.addingTimeInterval(14 * 60)
        let end = today.addingTimeInterval((7 * 60 + 38) * 60)
        let plan = Plan(day: WFormat.dayKey(today, .current),
                        bedtimeMinutes: 23 * 60 + 20,
                        wakeMinutes: 7 * 60 + 25,
                        windDownMinutes: 22 * 60 + 45,
                        predictedSleepMinutes: 7 * 60 + 35,
                        balanceChangeMinutes: 7,
                        alarmEnabled: true,
                        steps: [
                            Step(id: "caffeine", title: "Последний кофе до 14:00", short: "кофе до 14:00",
                                 minutes: 14 * 60, systemImage: "cup.and.saucer", status: .done),
                            Step(id: "screen", title: "Режим без экрана", short: "без экрана",
                                 minutes: 22 * 60 + 45, systemImage: "iphone.slash", status: .pending),
                            Step(id: "bedtime", title: "Лечь в кровать", short: "в кровать",
                                 minutes: 23 * 60 + 20, systemImage: "bed.double", status: .pending),
                        ])
        let pattern: [(Double, Double, Stage)] = [
            (0.00, 0.05, .core), (0.05, 0.13, .deep), (0.13, 0.22, .core), (0.22, 0.26, .rem),
            (0.26, 0.27, .awake), (0.27, 0.35, .core), (0.35, 0.40, .deep), (0.40, 0.50, .core),
            (0.50, 0.56, .rem), (0.56, 0.57, .awake), (0.57, 0.68, .core), (0.68, 0.71, .deep),
            (0.71, 0.78, .core), (0.78, 0.85, .rem), (0.85, 0.86, .awake), (0.86, 0.94, .core),
            (0.94, 1.00, .rem),
        ]
        let night = Night(sleepStart: start, sleepEnd: end, asleepMinutes: 7 * 60 + 14, goalMinutes: 7 * 60 + 42,
                          score: 78, scoreLabel: "В целом спокойно", norm: 74, recovery: "как обычно",
                          sourceName: "Apple Watch", syncedAt: end.addingTimeInterval(14 * 60),
                          stages: Stages(deep: 62, core: 246, rem: 106, awake: 20),
                          segments: pattern.map { Segment(start: $0.0, end: $0.1, stage: $0.2) })
        return WidgetSnapshot(generatedAt: Date(), timeZoneID: TimeZone.current.identifier, isOnboarded: true,
                              night: night, shortfall: Shortfall(minutes: 128, isPreliminary: false), plan: plan)
    }

    /// Today at a given local time — for Xcode previews.
    static func previewDate(hour: Int, minute: Int) -> Date {
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
