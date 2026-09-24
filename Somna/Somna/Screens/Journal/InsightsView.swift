//
//  InsightsView.swift
//  Somna
//
//  13 Journal insights: the strongest stable link in the person's own data,
//  compared across outcomes, plus the other links. Shown only with at least
//  6 nights in each group. A link is never presented as a cause.
//

import SwiftUI
import Foundation

struct InsightsView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let snapshot = store.snapshot
        let lead = strongest(snapshot)
        SomnaScreen(mode: mode) {
            if let lead {
                hero(p, lead: lead, snapshot: snapshot)
                comparison(p, lead: lead, snapshot: snapshot)
            } else {
                StateBlock(icon: "sparkles", state: .neutral, title: "Устойчивых закономерностей пока нет",
                           what: "Для сравнения нужно минимум \(FactorInsight.minimumPerGroup) ночей после дней с фактором и \(FactorInsight.minimumPerGroup) — без него. Отмечайте журнал каждый день.",
                           available: "Кофеин, тренировки, свет, шаги и дневной сон подтягиваются из Здоровья сами",
                           actionTitle: "Открыть журнал", actionIcon: "square.and.pencil") {
                    state.setPath([], for: .journal)
                    state.go(to: .journal)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 14, weight: .medium))
                    Text("Связь — ещё не причина")
                        .font(SomnaFont.body(15, .semibold))
                }
                Text("В такие дни могло совпасть что-то ещё: нагрузка, поздний отход ко сну, выходные. Чтобы понять, что работает именно у вас, проверьте одну привычку экспериментом.")
                    .font(SomnaFont.body(14))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(fill: p.surface2)

            others(p, lead: lead, snapshot: snapshot)

            if store.activeExperiment == nil {
                PrimaryButton(title: "Проверить экспериментом", systemImage: "flask") {
                    state.experimentFactorID = lead?.factorID
                    state.push(.experimentSetup)
                }
            } else {
                SecondaryButton(title: "Идёт эксперимент", systemImage: "flask") {
                    state.push(.experimentProgress)
                }
            }
        }
        .somnaNavTitle("Закономерности", mode: mode)
    }

    // MARK: Data

    /// The stable link with the largest effect on the score: 30 days first, then 90, then 7.
    private func strongest(_ snapshot: SomnaSnapshot) -> FactorInsight? {
        for window in [30, 90, 7] {
            let stable = snapshot.insights(window: window, outcome: .score).filter(\.isStable)
            if let best = stable.max(by: { abs($0.difference ?? 0) < abs($1.difference ?? 0) }) {
                return best
            }
        }
        return nil
    }

    private func sameFactor(_ lead: FactorInsight, _ snapshot: SomnaSnapshot) -> [FactorInsight] {
        OutcomeMetric.allCases.compactMap { outcome in
            snapshot.insights(window: lead.windowDays, outcome: outcome)
                .first { $0.factorID == lead.factorID && $0.hasEnoughData }
        }
    }

    // MARK: Sections

    private func hero(_ p: Palette, lead: FactorInsight, snapshot: SomnaSnapshot) -> some View {
        let factor = snapshot.factors.first { $0.id == lead.factorID }
        return VStack(alignment: .leading, spacing: 12) {
            Overline(icon: factor?.systemImage ?? "sparkles", iconColor: Brand.sunrise, text: "Самая заметная связь")
            Text(sentence(lead))
                .displayStyle(28, tracking: -0.9)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Text("\(lead.windowDays) дней · \(lead.withCount) ночей с фактором, \(lead.withoutCount) без")
                    .font(SomnaFont.body(12, .medium))
            }
            .foregroundStyle(p.fg2)
        }
    }

    private func sentence(_ lead: FactorInsight) -> String {
        let d = lead.outcome.formatDifference(lead.difference ?? 0)
        return lead.isUnfavourable
            ? "После дней с фактором «\(lead.title)» оценка сна ниже: \(d)"
            : "После дней с фактором «\(lead.title)» оценка сна выше: \(d)"
    }

    private func comparison(_ p: Palette, lead: FactorInsight, snapshot: SomnaSnapshot) -> some View {
        let rows = sameFactor(lead, snapshot)
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                LegendItem(color: p.fg, text: "с фактором")
                LegendItem(color: p.fg3, text: "без него")
            }
            ForEach(rows) { insight in
                if let with = insight.medianWith, let without = insight.medianWithout {
                    OutcomeComparison(insight: insight, with: with, without: without)
                }
            }
        }
        .card()
    }

    @ViewBuilder
    private func others(_ p: Palette, lead: FactorInsight?, snapshot: SomnaSnapshot) -> some View {
        let window = lead?.windowDays ?? 30
        let all = snapshot.insights(window: window, outcome: .score).filter { $0.factorID != lead?.factorID }
        let ready = all.filter(\.hasEnoughData).sorted { abs($0.difference ?? 0) > abs($1.difference ?? 0) }
        let waiting = all.filter { !$0.hasEnoughData && ($0.withCount + $0.withoutCount) > 0 }
        if !ready.isEmpty || !waiting.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Другие факторы · \(window) дней", action: "Все") {
                    state.push(.factors)
                }
                VStack(spacing: 0) {
                    ForEach(Array((ready + waiting).prefix(6).enumerated()), id: \.element.id) { index, insight in
                        let factor = snapshot.factors.first { $0.id == insight.factorID }
                        InsightRow(state: insight.isStable ? (insight.isUnfavourable ? .caution : .restore) : .neutral,
                                   icon: factor?.systemImage ?? "tag",
                                   title: title(insight),
                                   detail: detail(insight),
                                   metaIcon: factor?.healthDerived == true ? "heart.text.square" : "square.and.pencil",
                                   meta: insight.hasEnoughData ? (insight.isStable ? "устойчиво" : "неустойчиво") : "собираем данные",
                                   showDivider: index < min(6, ready.count + waiting.count) - 1)
                    }
                }
            }
        }
    }

    private func title(_ insight: FactorInsight) -> String {
        guard insight.hasEnoughData else { return "\(insight.title): недостаточно данных" }
        return "\(insight.title): оценка \(insight.outcome.formatDifference(insight.difference ?? 0))"
    }

    private func detail(_ insight: FactorInsight) -> String {
        guard insight.hasEnoughData else {
            return "С фактором \(insight.withCount), без — \(insight.withoutCount) ночей. Нужно по \(FactorInsight.minimumPerGroup)."
        }
        if insight.isStable { return "Разница держится при перепроверке на ваших данных." }
        return "Разница в пределах обычного разброса — выводов не делаем."
    }
}

private struct OutcomeComparison: View {
    @Environment(\.palette) private var p
    let insight: FactorInsight
    let with: Double
    let without: Double

    var body: some View {
        let top = max(with, without, 1) * 1.15
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(insight.outcome.title)
                    .font(SomnaFont.body(14, .medium))
                Spacer()
                Text(insight.outcome.formatDifference(insight.difference ?? 0))
                    .font(SomnaFont.body(13, .semibold))
                Text(insight.outcome.higherIsBetter ? "больше — лучше" : "меньше — лучше")
                    .font(SomnaFont.body(11))
                    .foregroundStyle(p.fg3)
            }
            bar(value: with, top: top, color: p.fg)
            bar(value: without, top: top, color: p.fg3)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(insight.outcome.title): \(format(with)) с фактором, \(format(without)) без него")
    }

    private func bar(value: Double, top: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            ProgressTrack(fraction: value / top, fill: color, height: 12)
            Text(format(value))
                .font(SomnaFont.body(13, .semibold))
                .frame(minWidth: 52, alignment: .trailing)
        }
    }

    private func format(_ v: Double) -> String {
        switch insight.outcome {
        case .score: "\(Int(v.rounded()))"
        case .asleep, .latency: Fmt.duration(v)
        case .energy: Fmt.number(v, digits: 1)
        }
    }
}
