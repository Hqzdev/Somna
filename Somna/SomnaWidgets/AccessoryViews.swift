//
//  AccessoryViews.swift
//  SomnaWidgets
//
//  Lock screen: inline, circular and rectangular (design board 21). The
//  system tints them over the wallpaper, so they use the system font and
//  no colors of their own.
//

import SwiftUI
import WidgetKit

struct InlineAccessoryView: View {
    let entry: SomnaEntry

    var body: some View {
        if !entry.hasData {
            Label("Somna", systemImage: "moon")
        } else if let night = entry.night {
            Label(night.score.map { "сон \($0)" } ?? "сон \(WFormat.hoursMinutes(night.asleepMinutes))",
                  systemImage: "moon")
        } else if entry.isPastBedtime, let wake = entry.wake {
            Label("подъём в \(entry.clock(wake))", systemImage: "alarm")
        } else if let bedtime = entry.bedtime {
            Label("лечь в \(entry.clock(bedtime))", systemImage: "moon")
        } else {
            Label("Somna", systemImage: "moon")
        }
    }
}

/// Ring gauge for the lock screen.
struct AccessoryRing: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.25), lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(4)
    }
}

struct AccessoryValue: View {
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: -2) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 9, weight: .medium))
                .lineLimit(1)
        }
    }
}

struct AccessoryIconValue: View {
    let systemImage: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.horizontal, 4)
    }
}

/// Morning: sleep score ring. Evening: minutes left to wind-down during the
/// last hour, otherwise bedtime.
struct CircularAccessoryView: View {
    let entry: SomnaEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            content
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        if !entry.hasData {
            Image(systemName: "moon.zzz")
                .font(.system(size: 20, weight: .medium))
        } else if let night = entry.night {
            if let score = night.score {
                AccessoryRing(fraction: Double(score) / 100)
                AccessoryValue(value: "\(score)", caption: "сон")
            } else {
                AccessoryIconValue(systemImage: "bed.double", value: WFormat.hoursMinutes(night.asleepMinutes))
            }
        } else if !entry.isPastBedtime, let minutes = entry.minutesToTarget, minutes > 0, minutes <= 60 {
            AccessoryRing(fraction: Double(minutes) / 60)
            AccessoryValue(value: "\(minutes)", caption: "мин")
        } else if entry.isPastBedtime, let wake = entry.wake {
            AccessoryIconValue(systemImage: "alarm", value: entry.clock(wake))
        } else if let bedtime = entry.bedtime {
            AccessoryIconValue(systemImage: "moon", value: entry.clock(bedtime))
        } else {
            Image(systemName: "moon.zzz")
                .font(.system(size: 20, weight: .medium))
        }
    }
}

/// Second circular widget: morning — time asleep, evening — bedtime.
struct ClockCircularView: View {
    let entry: SomnaEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if !entry.hasData {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 20, weight: .medium))
            } else if let night = entry.night {
                AccessoryIconValue(systemImage: "bed.double", value: WFormat.hoursMinutes(night.asleepMinutes))
            } else if entry.isPastBedtime, let wake = entry.wake {
                AccessoryIconValue(systemImage: "alarm", value: entry.clock(wake))
            } else if let bedtime = entry.bedtime {
                AccessoryIconValue(systemImage: "moon", value: entry.clock(bedtime))
            } else {
                Image(systemName: "moon.zzz")
                    .font(.system(size: 20, weight: .medium))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Morning: today's plan in two lines. Evening: the next two steps.
struct RectangularAccessoryView: View {
    let entry: SomnaEntry

    var body: some View {
        let lines = self.lines
        VStack(alignment: .leading, spacing: 1) {
            Label(lines.title, systemImage: lines.icon)
                .font(.system(size: 14, weight: .semibold))
                .widgetAccentable()
                .lineLimit(1)
            Text(lines.first)
                .font(.system(size: 14))
                .lineLimit(1)
            Text(lines.second)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var lines: (title: String, icon: String, first: String, second: String) {
        guard entry.hasData, let bedtime = entry.bedtime, let wake = entry.wake else {
            return ("Somna", "moon", "Откройте приложение,", "чтобы собрать план")
        }
        if entry.isPastBedtime {
            return ("Ночь", "alarm", "подъём в \(entry.clock(wake))",
                    entry.plan?.alarmEnabled == true ? "будильник включён" : "будильник выключен")
        }
        if entry.isMorning {
            if let windDown = entry.windDown {
                return ("Сегодня", "moon", "режим в \(entry.clock(windDown))", "лечь в \(entry.clock(bedtime))")
            }
            return ("Сегодня", "moon", "лечь в \(entry.clock(bedtime))", "подъём в \(entry.clock(wake))")
        }
        let timed = entry.steps.filter { $0.minutes != nil && entry.status(of: $0) == .pending }
        var rows = timed.prefix(2).map { step in "\(entry.clock(minutes: step.minutes ?? 0)) \(step.short)" }
        if rows.count < 2 { rows.append("подъём в \(entry.clock(wake))") }
        if rows.count < 2 { rows.insert("лечь в \(entry.clock(bedtime))", at: 0) }
        let title = entry.steps.isEmpty ? "План" : "План · \(entry.doneCount) из \(entry.steps.count)"
        return (title, "moon", rows[0], rows[1])
    }
}
