//
//  SomnaWidgets.swift
//  SomnaWidgets
//
//  iPhone widgets (design board 21): home screen S/M/L and lock screen
//  inline/circular/rectangular. Morning (05–15) shows the night result,
//  the rest of the day shows tonight's plan. Data comes from the App Group,
//  written by the app after every recompute.
//

import SwiftUI
import WidgetKit

// MARK: - Entry

struct SomnaEntry: TimelineEntry {
    let date: Date
    let data: WidgetSnapshot

    var timeZone: TimeZone { TimeZone(identifier: data.timeZoneID) ?? .current }

    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        return c
    }

    var hour: Int { calendar.component(.hour, from: date) }
    var isMorning: Bool { (5..<15).contains(hour) }
    var palette: WPalette { WPalette.at(hour: hour) }
    var hasData: Bool { data.isOnboarded && data.generatedAt != .distantPast }
    var isStale: Bool { date.timeIntervalSince(data.generatedAt) > 36 * 3600 }

    /// The night is shown only in the morning and only within 16 h of waking up.
    var night: WidgetSnapshot.Night? {
        guard hasData, isMorning, let n = data.night else { return nil }
        let since = date.timeIntervalSince(n.sleepEnd)
        return since >= 0 && since < 16 * 3600 ? n : nil
    }

    // MARK: Tonight

    /// Local midnight of the evening this moment belongs to (before 05:00 — the previous one).
    var eveningStart: Date {
        let start = calendar.startOfDay(for: date)
        guard hour < 5 else { return start }
        return calendar.date(byAdding: .day, value: -1, to: start) ?? start
    }

    func tonight(_ minutes: Int) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: eveningStart) ?? eveningStart
    }

    var plan: WidgetSnapshot.Plan? { hasData ? data.plan : nil }
    var bedtime: Date? { plan.map { tonight($0.bedtimeMinutes) } }
    var wake: Date? { plan.map { tonight($0.wakeMinutes + 1440) } }
    var windDown: Date? { plan?.windDownMinutes.map { tonight($0) } }

    var isPastBedtime: Bool {
        guard let bedtime, let wake else { return false }
        return date >= bedtime && date < wake
    }

    /// Countdown target on the lock screen: wind-down, or bedtime without one.
    var countdownTarget: Date? { windDown ?? bedtime }

    var minutesToTarget: Int? {
        guard let target = countdownTarget else { return nil }
        return Int((target.timeIntervalSince(date) / 60).rounded(.up))
    }

    /// Marks from the app count only for the plan of this evening.
    var planIsCurrent: Bool { plan?.day == WFormat.dayKey(eveningStart, timeZone) }

    func status(of step: WidgetSnapshot.Step) -> WidgetSnapshot.StepStatus {
        planIsCurrent ? step.status : .pending
    }

    var steps: [WidgetSnapshot.Step] { plan?.steps ?? [] }
    var doneCount: Int { steps.filter { status(of: $0) == .done }.count }
    var currentStepID: String? { steps.first { status(of: $0) == .pending }?.id }

    func clock(_ date: Date) -> String { WFormat.clock(date, timeZone) }
    func clock(minutes: Int) -> String { clock(tonight(minutes)) }

    var link: URL {
        guard hasData else { return URL(string: "somna://today")! }
        return URL(string: night != nil ? "somna://night" : "somna://plan")!
    }

    var relevance: TimelineEntryRelevance? {
        if let m = minutesToTarget, m > 0, m <= 90 { return TimelineEntryRelevance(score: 80, duration: 15 * 60) }
        if night != nil { return TimelineEntryRelevance(score: 50) }
        return TimelineEntryRelevance(score: 5)
    }
}

// MARK: - Timeline

struct SomnaProvider: TimelineProvider {
    func placeholder(in context: Context) -> SomnaEntry {
        SomnaEntry(date: Date(), data: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (SomnaEntry) -> Void) {
        let stored = WidgetSnapshotStore.load()
        let data = context.isPreview && stored.generatedAt == .distantPast ? WidgetSnapshot.preview : stored
        completion(SomnaEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SomnaEntry>) -> Void) {
        let now = Date()
        let data = WidgetSnapshotStore.load()
        let entries = Self.updateDates(from: now, data: data).map { SomnaEntry(date: $0, data: data) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    /// Moments within the next 24 h when the content changes: palette hours,
    /// wind-down, bedtime, wake-up, end of the night window and a minute-by-minute
    /// countdown during the last hour before wind-down.
    static func updateDates(from now: Date, data: WidgetSnapshot) -> [Date] {
        let probe = SomnaEntry(date: now, data: data)
        let calendar = probe.calendar
        let today = calendar.startOfDay(for: now)
        var dates: Set<Date> = [now]
        for offset in -1...1 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for hour in [5, 15, 18, 21] {
                if let d = calendar.date(byAdding: .hour, value: hour, to: day) { dates.insert(d) }
            }
            guard let plan = data.plan else { continue }
            var marks = [plan.bedtimeMinutes, plan.wakeMinutes + 1440]
            if let w = plan.windDownMinutes { marks.append(w) }
            for m in marks {
                if let d = calendar.date(byAdding: .minute, value: m, to: day) { dates.insert(d) }
            }
            if let target = calendar.date(byAdding: .minute, value: plan.windDownMinutes ?? plan.bedtimeMinutes, to: day) {
                for k in 1...60 { dates.insert(target.addingTimeInterval(Double(-k * 60))) }
            }
        }
        if let n = data.night { dates.insert(n.sleepEnd.addingTimeInterval(16 * 3600)) }
        let end = now.addingTimeInterval(24 * 3600)
        return dates.filter { $0 >= now && $0 <= end }.sorted()
    }
}

// MARK: - Widgets

struct SomnaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: SomnaProvider()) { entry in
            SomnaWidgetView(entry: entry)
        }
        .configurationDisplayName("Somna")
        .description("Утром — итог ночи, вечером — план и время отхода ко сну.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct SomnaClockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.clockKind, provider: SomnaProvider()) { entry in
            ClockCircularView(entry: entry)
                .widgetURL(entry.link)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Somna · время")
        .description("Утром — сколько вы спали, вечером — во сколько лечь.")
        .supportedFamilies([.accessoryCircular])
    }
}

@main
struct SomnaWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SomnaWidget()
        SomnaClockWidget()
    }
}

// MARK: - Previews

#Preview("Утро · S", as: .systemSmall) {
    SomnaWidget()
} timeline: {
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 8, minute: 4), data: .preview)
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 22, minute: 31), data: .preview)
}

#Preview("M", as: .systemMedium) {
    SomnaWidget()
} timeline: {
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 8, minute: 4), data: .preview)
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 22, minute: 31), data: .preview)
}

#Preview("L", as: .systemLarge) {
    SomnaWidget()
} timeline: {
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 8, minute: 4), data: .preview)
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 22, minute: 31), data: .preview)
}

#Preview("Экран блокировки", as: .accessoryRectangular) {
    SomnaWidget()
} timeline: {
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 8, minute: 4), data: .preview)
    SomnaEntry(date: WidgetSnapshot.previewDate(hour: 22, minute: 31), data: .preview)
}
