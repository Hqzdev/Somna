//
//  NightReviewView.swift
//  Somna
//
//  05 Night review: explains one recorded night against the person's own
//  history instead of just listing metrics. Root of the «Сон» tab.
//

import SwiftUI
import Foundation

struct NightReviewView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    /// nil = the night selected in the tab (or the latest one).
    let day: DayKey?

    init(day: DayKey?) {
        self.day = day
    }

    private var reports: [NightReport] { store.snapshot.reports }

    private var current: NightReport? {
        let wanted = day ?? state.selectedNight
        if let wanted, let r = store.snapshot.report(for: wanted) { return r }
        return reports.last
    }

    var body: some View {
        let mode = state.timeOfDay
        Group {
            if let report = current {
                content(report, mode: mode)
            } else {
                SomnaScreen(mode: mode) {
                    StateBlock(icon: "moon.zzz", state: .neutral, title: "Ночей пока нет",
                               what: store.healthRequested || store.usesDemoData
                                   ? "Разбор появится утром после первой записанной ночи."
                                   : "Подключите Apple Health — без него Somna не видит сон.",
                               actionTitle: store.healthRequested || store.usesDemoData ? nil : "Подключить Apple Health",
                               actionIcon: "heart.text.square") {
                        Task { await store.connectHealth() }
                    }
                }
                .somnaNavTitle("Сон", mode: mode)
            }
        }
    }

    private func content(_ report: NightReport, mode: TimeOfDay) -> some View {
        let history = reports.filter { $0.dayKey < report.dayKey }
        return SomnaScreen(mode: mode, spacing: 28) {
            ScoreBaselineCard(report: report, history: history)
            NightTimelineSection(night: report.night)
            KeyStatsList(report: report, history: Array(history.suffix(14)), goal: report.goalMinutes)
            if report.night.stages.hasDetailedStages {
                HypnogramCard(night: report.night)
            } else {
                StateBlock(icon: "chart.bar.xaxis", state: .neutral, title: "Стадии не записаны",
                           what: "Этот источник записывает только время сна. Стадии появятся с Apple Watch.",
                           available: "Длительность известна; непрерывность и общий балл могут быть недоступны")
            }
            HeartCard(report: report, history: Array(history.suffix(28)))
            EveningFactors(report: report, snapshot: store.snapshot)
            VStack(spacing: 6) {
                PrimaryButton(title: "Посмотреть, что изменить сегодня") {
                    state.go(to: .plan)
                }
                TextLink(title: "Факторы и связи со сном") {
                    state.push(.factors)
                }
            }
            more
        }
        .somnaNavTitle("Ночь на \(Fmt.dayMonth(report.dayKey))", subtitle: Fmt.nightSpan(report.dayKey), mode: mode)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    move(from: report, by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(neighbour(of: report, by: -1) == nil)
                .accessibilityLabel("Предыдущая ночь")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    move(from: report, by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(neighbour(of: report, by: 1) == nil)
                .accessibilityLabel("Следующая ночь")
            }
        }
        .refreshable { await store.refreshHealth() }
    }

    private func neighbour(of report: NightReport, by offset: Int) -> NightReport? {
        guard let index = reports.firstIndex(where: { $0.dayKey == report.dayKey }) else { return nil }
        let target = index + offset
        return reports.indices.contains(target) ? reports[target] : nil
    }

    private func move(from report: NightReport, by offset: Int) {
        guard let next = neighbour(of: report, by: offset) else { return }
        if day == nil {
            state.selectedNight = next.dayKey
        } else {
            state.push(.nightReview(next.dayKey))
        }
    }

    private var more: some View {
        let snapshot = store.snapshot
        return VStack(alignment: .leading, spacing: 8) {
            GroupCaption(text: "Подробнее о сне")
            GroupedList {
                MetricRow(state: nil, label: "Баланс сна", sub: "14 ночей", value: snapshot.balance?.text ?? "—") { state.push(.sleepDebt) }
                MetricRow(state: nil, label: "Спальня", sub: "Ваши отметки о комнате", value: "") { state.push(.environment) }
                MetricRow(state: nil, label: "Ритм и поездки", sub: "Регулярность", value: snapshot.regularity?.scoreText ?? "—") { state.push(.circadian) }
                MetricRow(state: nil, label: "Сигналы здоровья", sub: "7 ночей против 28 предыдущих",
                          value: signalCount(snapshot), showDivider: false) { state.push(.healthSignals) }
            }
        }
    }

    private func signalCount(_ snapshot: SomnaSnapshot) -> String {
        let n = snapshot.trends.filter(\.isSustained).count
        return n == 0 ? "Без изменений" : "\(n) \(CoreFormat.plural(n, "изменение", "изменения", "изменений"))"
    }
}

// MARK: - Score vs the last 30 nights

private struct ScoreBaselineCard: View {
    @Environment(\.palette) private var p
    let report: NightReport
    let history: [NightReport]

    var body: some View {
        let scores = history.suffix(30).compactMap { $0.score.map { Double($0.value) } }
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Text(report.score.map { "\($0.value)" } ?? "—")
                    .font(SomnaFont.display(64, relativeTo: .largeTitle))
                    .tracking(-2.8)
                VStack(alignment: .leading, spacing: 6) {
                    if let score = report.score {
                        StatusTag(text: score.label, state: score.signal)
                    }
                    Text(caption(scores))
                        .font(SomnaFont.body(14))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            if let value = report.score?.value, scores.count >= 7,
               let median = Stats.median(scores),
               let lo = Stats.quantile(scores, 0.25), let hi = Stats.quantile(scores, 0.75) {
                BaselineScale(value: Double(value), usualLow: lo, usualHigh: hi, baseline: median)
            }
            if let explanation = report.explanation {
                Text(explanation)
                    .font(SomnaFont.body(15))
                    .fixedSize(horizontal: false, vertical: true)
            }
            componentLine
        }
        .card(padding: 24, radius: Radius.hero)
    }

    private func caption(_ scores: [Double]) -> String {
        guard let value = report.score?.value else {
            return report.explanation ?? "Для общего балла нужны надёжные данные о длительности, непрерывности и режиме."
        }
        guard scores.count >= 7, let median = Stats.median(scores) else {
            return "Сравнение с вашей нормой — через \(Fmt.nights(7 - scores.count))."
        }
        let diff = value - Int(median.rounded())
        if diff == 0 { return "Как ваша медиана за \(Fmt.nights(scores.count))" }
        return "На \(abs(diff)) \(CoreFormat.plural(abs(diff), "балл", "балла", "баллов")) \(diff > 0 ? "выше" : "ниже") вашей медианы за \(Fmt.nights(scores.count))"
    }

    @ViewBuilder
    private var componentLine: some View {
        let c = report.scoreComponents
        if c.duration != nil {
            HStack(spacing: 14) {
                component("Достаточно", c.duration)
                component("Непрерывно", c.continuity)
                component("Ритм", c.regularity)
            }
            .padding(.top, 4)
        }
    }

    private func component(_ title: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(SomnaFont.body(11))
                .foregroundStyle(p.fg2)
            Text(value.map { "\(Int($0.rounded()))" } ?? "нет данных")
                .font(SomnaFont.body(14, .semibold))
                .foregroundStyle(value == nil ? p.fg3 : p.fg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Timeline from bed to wake

private struct NightTimelineSection: View {
    @Environment(\.palette) private var p
    let night: SleepNight

    private var events: [(Color?, String, String, String)] {
        let tz = night.timeZone
        var list: [(Color?, String, String, String)] = []
        if let bed = night.inBedStart {
            list.append((nil, "Легли в кровать", "", Fmt.time(bed, tz)))
        }
        list.append((Brand.ink, "Уснули", night.latencyMinutes.map { "засыпание \(Fmt.duration($0))" } ?? "", Fmt.time(night.sleepStart, tz)))
        if night.awakenings > 0 {
            list.append((Brand.caution, "Пробуждения", "всего \(Fmt.duration(night.awake / 60))", "\(night.awakenings) \(CoreFormat.plural(night.awakenings, "раз", "раза", "раз"))"))
        }
        list.append((Brand.restore, "Проснулись", night.timeZoneChanged ? "другой часовой пояс" : "", Fmt.time(night.sleepEnd, tz)))
        return list
    }

    var body: some View {
        let start = night.inBedStart ?? night.sleepStart
        let end = max(night.inBedEnd ?? night.sleepEnd, night.sleepEnd)
        VStack(alignment: .leading, spacing: 14) {
            ChartHeader(title: "От кровати до подъёма",
                        range: "\(Fmt.time(start, night.timeZone)) → \(Fmt.time(end, night.timeZone)) · \(Fmt.duration(end.timeIntervalSince(start) / 60))")
            NightStrip(night: night)
            VStack(spacing: 0) {
                ForEach(events.indices, id: \.self) { i in
                    let e = events[i]
                    HStack(spacing: 12) {
                        Circle()
                            .fill(e.0 ?? p.cautionSoft)
                            .overlay(Circle().stroke(p.lineStrong, lineWidth: e.0 == nil ? 1 : 0))
                            .frame(width: 8, height: 8)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.1)
                                .font(SomnaFont.body(14, .medium))
                            if !e.2.isEmpty {
                                Text(e.2)
                                    .font(SomnaFont.body(12))
                                    .foregroundStyle(p.fg2)
                            }
                        }
                        Spacer()
                        Text(e.3)
                            .font(SomnaFont.body(13, .semibold))
                            .foregroundStyle(p.fg2)
                    }
                    .padding(.vertical, 11)
                    .overlay(alignment: .bottom) {
                        if i < events.count - 1 { Divider1() }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .card(padding: 0, radius: Radius.row)
        }
    }
}

// MARK: - Key stats vs the usual (median of the previous 14 nights)

private struct KeyStatsList: View {
    @Environment(\.palette) private var p
    let report: NightReport
    let history: [NightReport]
    let goal: Int

    private var rows: [(String, String, String)] {
        let n = report.night
        let past = history.map(\.night).filter(\.isValid)
        func usual(_ values: [Double], _ format: (Double) -> String) -> String {
            guard values.count >= 5, let m = Stats.median(values) else { return "" }
            return "обычно \(format(m))"
        }
        var list: [(String, String, String)] = []
        if let tib = n.timeInBed {
            list.append(("Время в кровати", Fmt.duration(tib / 60), usual(past.compactMap { $0.timeInBed.map { $0 / 60 } }) { Fmt.duration($0) }))
        }
        list.append(("Время сна", Fmt.duration(n.asleepMinutes), "цель \(Fmt.duration(goal))"))
        if let l = n.latencyMinutes {
            list.append(("Засыпание", Fmt.duration(l), usual(past.compactMap(\.latencyMinutes)) { Fmt.duration($0) }))
        }
        list.append(("Пробуждения", "\(n.awakenings)", usual(past.map { Double($0.awakenings) }) { "\(Int($0.rounded()))" }))
        // In-bed shorter than sleep would cap at a false 100 %.
        if let e = n.efficiency, n.measurements.timeInBed.status == .measured {
            list.append(("Эффективность сна", Fmt.percent(e), usual(past.compactMap(\.efficiency)) { Fmt.percent($0) }))
        }
        return list
    }

    var body: some View {
        let rows = self.rows
        GroupedList {
            ForEach(rows.indices, id: \.self) { i in
                HStack(alignment: .lastTextBaseline) {
                    Text(rows[i].0)
                        .font(SomnaFont.body(14))
                        .foregroundStyle(p.fg2)
                    Spacer()
                    Text(rows[i].2)
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg3)
                    Text(rows[i].1)
                        .font(SomnaFont.body(15, .semibold))
                }
                .padding(.vertical, 13)
                .overlay(alignment: .bottom) {
                    if i < rows.count - 1 { Divider1() }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Hypnogram

private struct HypnogramCard: View {
    @Environment(\.palette) private var p
    let night: SleepNight

    var body: some View {
        let s = night.stages
        let asleep = max(night.asleep, 1)
        let totals: [(SleepStage, String)] = [
            (.deep, "\(Fmt.duration(s.deep / 60)) · \(Int((s.deep / asleep * 100).rounded()))%"),
            (.rem, "\(Fmt.duration(s.rem / 60)) · \(Int((s.rem / asleep * 100).rounded()))%"),
            (.core, "\(Fmt.duration(s.core / 60)) · \(Int((s.core / asleep * 100).rounded()))%"),
            (.awake, "\(Fmt.duration(night.awake / 60)) · \(night.awakenings) \(CoreFormat.plural(night.awakenings, "раз", "раза", "раз"))")
        ]
        VStack(alignment: .leading, spacing: 16) {
            ChartHeader(title: "Стадии сна",
                        range: "\(Fmt.time(night.sleepStart, night.timeZone))–\(Fmt.time(night.sleepEnd, night.timeZone))")
            HypnogramChart(night: night)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    total(totals[0])
                    total(totals[1])
                }
                GridRow {
                    total(totals[2])
                    total(totals[3])
                }
            }
            Text("Стадии определяются приблизительно и не влияют на балл без проверки по вашим утренним оценкам.")
                .font(SomnaFont.body(13))
                .foregroundStyle(p.fg2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card()
    }

    private func total(_ item: (SleepStage, String)) -> some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(item.0.color(p))
                .frame(width: 10, height: 10)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.0 == .awake ? "Бодрствование" : item.0.title)
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg2)
                Text(item.1)
                    .font(SomnaFont.body(14, .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Heart rate & HRV against the person's own history

private struct HeartCard: View {
    @Environment(\.palette) private var p
    let report: NightReport
    let history: [NightReport]

    private var hrvBaseline: MetricBaseline? { report.recovery?.hrvBaseline }

    var body: some View {
        let averages = history.compactMap { $0.vitals.heartRate?.average }
        let bandLow = averages.count >= 7 ? Stats.quantile(averages, 0.25) : nil
        let bandHigh = averages.count >= 7 ? Stats.quantile(averages, 0.75) : nil
        if report.vitals.heartRate != nil || report.vitals.hrv != nil {
            VStack(alignment: .leading, spacing: 16) {
                if let rate = report.vitals.heartRate {
                    ChartHeader(title: "Пульс во сне",
                                range: "среднее \(Int(rate.average.rounded())) · минимум \(Int(rate.minimum.rounded())) уд/мин") {
                        if bandLow != nil {
                            LegendItem(color: p.accentSoft, text: "Обычно", width: 14, height: 8)
                        }
                    }
                    if rate.series.compactMap({ $0 }).count >= 3 {
                        HeartRateChart(rate: rate, timeZone: report.night.timeZone, bandLow: bandLow, bandHigh: bandHigh)
                    }
                }
                if let hrv = report.vitals.hrv {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ВСР во сне")
                                .font(SomnaFont.body(14, .semibold))
                            Text(hrvText(hrv))
                                .font(SomnaFont.body(12))
                                .foregroundStyle(p.fg2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if let b = hrvBaseline {
                            let z = b.z(hrv)
                            StatusTag(text: abs(z) <= 1 ? "Как обычно" : (z < 0 ? "Ниже обычного" : "Выше обычного"),
                                      state: z < -1 ? .caution : .neutral)
                        }
                    }
                    .padding(.top, report.vitals.heartRate == nil ? 0 : 14)
                    .overlay(alignment: .top) {
                        if report.vitals.heartRate != nil { Divider1() }
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("Это наблюдение относительно вашей нормы, а не диагноз.")
                    .font(SomnaFont.body(12))
                    .foregroundStyle(p.fg3)
            }
            .card()
        }
    }

    private func hrvText(_ value: Double) -> String {
        guard let b = hrvBaseline else {
            return "\(Int(value.rounded())) мс · личная норма появится после 14 измерений"
        }
        let lo = Int((b.median - b.scale).rounded())
        let hi = Int((b.median + b.scale).rounded())
        return "\(Int(value.rounded())) мс · ваша медиана \(Int(b.median.rounded())) мс, обычно \(lo)–\(hi)"
    }
}

// MARK: - Factors of the evening before

private struct EveningFactors: View {
    @Environment(\.palette) private var p
    let report: NightReport
    let snapshot: SomnaSnapshot

    var body: some View {
        let factorDay = report.dayKey.adding(days: -1)
        let known = snapshot.factors.compactMap { f -> (JournalFactor, Double)? in
            guard let v = snapshot.factorValues[f.id]?[factorDay] else { return nil }
            return (f, v)
        }
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: "Вечер перед сном")
            if known.isEmpty {
                Text("Нет данных о факторах этого дня. Отметки в журнале помогут найти, что влияет на ваш сон.")
                    .font(SomnaFont.body(14))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(known.enumerated()), id: \.offset) { index, item in
                        let insight = snapshot.factorInsights
                            .filter { $0.factorID == item.0.id && $0.outcome == .score && $0.hasEnoughData }
                            .max { $0.windowDays < $1.windowDays }
                        InsightRow(state: item.0.isPresent(item.1) ? (insight?.isUnfavourable == true ? .caution : .neutral) : .restore,
                                   icon: item.0.systemImage,
                                   title: "\(item.0.title): \(valueText(item.0, item.1))",
                                   detail: detail(insight),
                                   metaIcon: item.0.healthDerived ? "heart.text.square" : "square.and.pencil",
                                   meta: item.0.healthDerived ? "Журнал или Apple Health" : "Журнал",
                                   showDivider: index < known.count - 1)
                    }
                }
            }
        }
    }

    private func valueText(_ f: JournalFactor, _ v: Double) -> String {
        switch f.kind {
        case .yesNo: v >= 1 ? "да" : "нет"
        case .scale: "\(Int(v)) из 5"
        case .count: "\(Int(v))"
        case .minutes: "\(Int(v)) мин"
        case .steps: "\(Int(v))"
        }
    }

    private func detail(_ insight: FactorInsight?) -> String {
        guard let i = insight, let d = i.difference else {
            return "Связь со сном пока не видна: нужно минимум 6 ночей с фактором и 6 без него."
        }
        let stable = i.isStable ? "устойчиво" : "неустойчиво"
        return "За \(i.windowDays) дней оценка в ночи после такого дня \(i.outcome.formatDifference(d)) (\(i.withCount) и \(i.withoutCount) ночей, \(stable)). Это связь, не причина."
    }
}
