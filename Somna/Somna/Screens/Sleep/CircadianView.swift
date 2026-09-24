//
//  CircadianView.swift
//  Somna
//
//  16 Rhythm: regularity from the mean deviation of sleep onset and wake
//  time over the last 14 nights, weekday vs weekend shift and time-zone
//  changes (travel). Local clock time is used everywhere.
//

import SwiftUI
import Foundation

struct CircadianView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let snapshot = store.snapshot
        let valid = snapshot.reports.map(\.night).filter(\.isValid)
        let recent = Array(valid.suffix(RegularityReport.window))
        SomnaScreen(mode: mode, spacing: 24) {
            if let r = snapshot.regularity {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(r.scoreText)
                            .font(SomnaFont.display(56, relativeTo: .largeTitle))
                            .tracking(-2)
                        VStack(alignment: .leading, spacing: 4) {
                            StatusTag(text: r.score >= 80 ? "Ровный режим" : (r.score >= 60 ? "Режим плавает" : "Режим сильно плавает"),
                                      state: Signal.regularity(r.score))
                            Text(r.isPreliminary ? "Предварительно · \(Fmt.nights(r.nights))" : "За \(Fmt.nights(r.nights))")
                                .font(SomnaFont.body(12))
                                .foregroundStyle(p.fg2)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    RegularityChart(nights: recent, medianBedtime: r.medianBedtime, medianWake: r.medianWake)
                }
                .card(padding: 22, radius: Radius.hero)

                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Ваш ритм")
                    GroupedList {
                        MetricRow(state: nil, label: "Обычно засыпаете",
                                  sub: "разброс ±\(Int(r.bedtimeMAD.rounded())) мин",
                                  value: Fmt.clock(ClockTime.minutesOfDay(fromBedtimeScale: r.medianBedtime)), showChevron: false)
                        MetricRow(state: nil, label: "Обычно просыпаетесь",
                                  sub: "разброс ±\(Int(r.wakeMAD.rounded())) мин",
                                  value: Fmt.clock(r.medianWake), showChevron: false,
                                  showDivider: socialShift(valid) != nil)
                        if let shift = socialShift(valid) {
                            MetricRow(state: abs(shift) >= 60 ? .caution : .neutral, label: "Выходные против будней",
                                      sub: "подъём в выходные по сравнению с буднями, 30 ночей",
                                      value: Fmt.signed(shift), showChevron: false, showDivider: false)
                        }
                    }
                }
            } else {
                StateBlock(icon: "clock.arrow.circlepath", state: .neutral,
                           title: snapshot.regularityNightsMissing > 0
                               ? "Регулярность посчитается через \(Fmt.nights(snapshot.regularityNightsMissing))"
                               : "Регулярность не считается при сменном графике",
                           what: "Считаем, насколько время засыпания и подъёма отклоняется от ваших обычных значений за 14 ночей.",
                           available: valid.isEmpty ? nil : "Уже записано: \(Fmt.nights(valid.count))")
            }

            let changes = snapshot.reports.suffix(60).filter(\.night.timeZoneChanged)
            if !changes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Смена часового пояса")
                    GroupedList {
                        ForEach(Array(changes.enumerated()), id: \.offset) { index, r in
                            MetricRow(state: .data, label: Fmt.dayMonth(r.dayKey),
                                      sub: zoneName(r.night.timeZone),
                                      value: offsetText(r.night.timeZone), showChevron: false,
                                      showDivider: index < changes.count - 1)
                        }
                    }
                    Text("Время ночей показано по местным часам. После перелёта ритм обычно подстраивается на 1–1,5 часа в сутки.")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                GroupCaption(text: "Как считаем")
                VStack(alignment: .leading, spacing: 8) {
                    IconLine(systemImage: "function", text: "Регулярность = 100 × (1 − среднее отклонение / 120 мин) по засыпанию и подъёму за 14 ночей.")
                    IconLine(systemImage: "sunrise", text: "Самый сильный рычаг — одно и то же время подъёма, включая выходные.")
                }
                .card(padding: 18, radius: Radius.row)
            }
        }
        .somnaNavTitle("Ритм и поездки", mode: mode)
    }

    /// Median weekend wake − median weekday wake over the last 30 nights.
    private func socialShift(_ nights: [SleepNight]) -> Double? {
        let recent = nights.suffix(30)
        let weekend = recent.filter { Fmt.isWeekend($0.dayKey) }.map(\.wakeScale)
        let weekday = recent.filter { !Fmt.isWeekend($0.dayKey) }.map(\.wakeScale)
        guard weekend.count >= 2, weekday.count >= 4,
              let a = Stats.median(weekend), let b = Stats.median(weekday) else { return nil }
        return a - b
    }

    private func zoneName(_ tz: TimeZone) -> String {
        tz.localizedName(for: .generic, locale: Locale(identifier: "ru_RU")) ?? tz.identifier
    }

    private func offsetText(_ tz: TimeZone) -> String {
        let hours = Double(tz.secondsFromGMT()) / 3600
        let text = hours == hours.rounded() ? "\(Int(hours))" : Fmt.number(hours, digits: 1)
        return "UTC\(hours >= 0 ? "+" : "")\(text)"
    }
}
