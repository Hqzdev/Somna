import SwiftUI
import WidgetKit

private struct SomnaEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot

    var isEvening: Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 18 || hour < 4
    }
}

private struct SomnaProvider: TimelineProvider {
    func placeholder(in context: Context) -> SomnaEntry {
        SomnaEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SomnaEntry) -> Void) {
        completion(SomnaEntry(date: Date(), snapshot: WatchSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SomnaEntry>) -> Void) {
        let now = Date()
        let snapshot = WatchSnapshotStore.load()
        let nextChange = nextTimeOfDayChange(after: now)
        let entries = [now, nextChange].map { SomnaEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(nextChange.addingTimeInterval(3600))))
    }

    private func nextTimeOfDayChange(after date: Date) -> Date {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let nextHour = hour < 4 ? 4 : (hour < 18 ? 18 : 4)
        return calendar.nextDate(after: date, matching: DateComponents(hour: nextHour), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(3600)
    }
}

private enum WidgetPalette {
    static let ink = Color(red: 0.08, green: 0.08, blue: 0.50)
    static let accent = Color(red: 0.62, green: 0.67, blue: 1.00)
    static let sunrise = Color(red: 1.00, green: 0.58, blue: 0.40)
}

private struct SleepWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SomnaEntry

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            default: rectangular
            }
        }
        .widgetURL(URL(string: entry.isEvening ? "somna-watch://plan" : "somna-watch://sleep"))
        .containerBackground(for: .widget) {
            if entry.isEvening {
                LinearGradient(colors: [.init(red: 0.17, green: 0.16, blue: 0.41), .init(red: 0.04, green: 0.04, blue: 0.20)],
                               startPoint: .top, endPoint: .bottom)
            } else {
                LinearGradient(colors: [.init(red: 1.00, green: 0.88, blue: 0.79), .init(red: 0.98, green: 0.96, blue: 0.94)],
                               startPoint: .top, endPoint: .bottom)
            }
        }
    }

    private var circular: some View {
        Group {
            if entry.snapshot.hasRecentSleep(at: entry.date), let score = entry.snapshot.sleepScore {
                Gauge(value: Double(score), in: 0...100) {
                    Text("Сон")
                } currentValueLabel: {
                    Text("\(score)").font(.system(.title3, design: .rounded, weight: .bold))
                }
                .gaugeStyle(.accessoryCircular)
                .tint(WidgetPalette.accent)
            } else {
                Image(systemName: "moon.zzz")
                    .font(.title3)
            }
        }
        .accessibilityLabel(entry.snapshot.sleepScore.map { "Оценка сна \($0)" } ?? "Нет данных о сне")
    }

    private var inline: some View {
        Group {
            if entry.snapshot.hasRecentSleep(at: entry.date), let minutes = entry.snapshot.sleepMinutes {
                Label("Сон \(WatchSnapshot.duration(minutes))", systemImage: "moon")
            } else {
                Label("Ждём данные о сне", systemImage: "moon")
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(entry.isEvening ? "СЕГОДНЯ ЛЕЧЬ" : "ПРОШЛАЯ НОЧЬ",
                  systemImage: entry.isEvening ? "moon" : "sunrise")
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)

            if entry.snapshot.updatedAt == .distantPast {
                Text("Откройте Somna")
                    .font(.headline)
            } else if entry.snapshot.isStale(at: entry.date) {
                Text("Обновите Somna")
                    .font(.headline)
            } else if entry.isEvening {
                Text(WatchSnapshot.clock(entry.snapshot.bedtimeMinutes))
                    .font(.system(size: 25, weight: .medium, design: .rounded))
                Text("Подъём в \(WatchSnapshot.clock(entry.snapshot.wakeMinutes))")
                    .font(.caption2)
            } else if entry.snapshot.hasRecentSleep(at: entry.date), let minutes = entry.snapshot.sleepMinutes {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let score = entry.snapshot.sleepScore {
                        Text("\(score)")
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                    }
                    Text(WatchSnapshot.duration(minutes))
                        .font(.caption)
                        .lineLimit(1)
                }
                Text("Сегодня лечь в \(WatchSnapshot.clock(entry.snapshot.bedtimeMinutes))")
                    .font(.caption2)
            } else {
                Text("Ждём данные о сне")
                    .font(.headline)
                Text("Откройте Somna")
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(renderingMode == .fullColor && !entry.isEvening ? WidgetPalette.ink : .primary)
    }
}

private struct AlarmWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: SomnaEntry

    var body: some View {
        Group {
            if family == .accessoryCorner {
                Image(systemName: "alarm")
                    .font(.title3)
                    .widgetLabel {
                        Text(entry.snapshot.alarmEnabled ? WatchSnapshot.clock(entry.snapshot.wakeMinutes) : "Выкл")
                    }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Label("БУДИЛЬНИК", systemImage: "alarm")
                        .font(.system(size: 10, weight: .bold))
                    if entry.snapshot.updatedAt == .distantPast {
                        Text("Откройте Somna")
                            .font(.headline)
                    } else if entry.snapshot.isStale(at: entry.date) {
                        Text("Проверьте на iPhone")
                            .font(.headline)
                    } else if entry.snapshot.alarmEnabled {
                        Text(WatchSnapshot.clock(entry.snapshot.wakeMinutes))
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                        Text("Каждый день · включён")
                            .font(.caption2)
                    } else {
                        Text("Выключен")
                            .font(.headline)
                        Text("Настроить подъём")
                            .font(.caption2)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .foregroundStyle(renderingMode == .fullColor ? .white : .primary)
            }
        }
        .widgetURL(URL(string: "somna-watch://alarm"))
        .containerBackground(for: .widget) {
            LinearGradient(colors: [.init(red: 0.22, green: 0.18, blue: 0.43), .init(red: 0.07, green: 0.07, blue: 0.29)],
                           startPoint: .top, endPoint: .bottom)
        }
        .tint(WidgetPalette.sunrise)
    }
}

private struct SomnaSleepWidget: Widget {
    let kind = "SomnaSleep"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SomnaProvider()) { entry in
            SleepWidgetView(entry: entry)
        }
        .configurationDisplayName("Сон и вечер")
        .description("Итог последней ночи и время, когда пора лечь.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular])
    }
}

private struct SomnaAlarmWidget: Widget {
    let kind = "SomnaAlarm"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SomnaProvider()) { entry in
            AlarmWidgetView(entry: entry)
        }
        .configurationDisplayName("Будильник Somna")
        .description("Время подъёма и состояние будильника.")
        .supportedFamilies([.accessoryCorner, .accessoryRectangular])
    }
}

@main
struct SomnaWatchWidgets: WidgetBundle {
    var body: some Widget {
        SomnaSleepWidget()
        SomnaAlarmWidget()
    }
}
