//
//  FactorsView.swift
//  Somna
//
//  06 Factors: for 7 / 30 / 90 days, the median result of nights after days
//  with a factor versus without it. Shows the difference, the sample sizes
//  and the uncertainty. A stable link is still a link, never a cause.
//

import SwiftUI
import Foundation

struct FactorsView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store
    @State private var windowIndex = 1
    @State private var outcomeIndex = 0

    private let windows = FactorInsight.windows
    private let outcomes: [OutcomeMetric] = [.score, .asleep]

    var body: some View {
        let mode = state.timeOfDay
        let p = mode.palette
        let insights = store.snapshot.insights(window: windows[windowIndex], outcome: outcomes[outcomeIndex])
        let ready = insights.filter(\.hasEnoughData).sorted { abs($0.difference ?? 0) > abs($1.difference ?? 0) }
        let waiting = insights.filter { !$0.hasEnoughData && ($0.withCount + $0.withoutCount) > 0 }
            .sorted { min($0.withCount, $0.withoutCount) > min($1.withCount, $1.withoutCount) }
        SomnaScreen(mode: mode, spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                SomnaSegmented(options: ["7 дней", "30 дней", "90 дней"], selection: $windowIndex)
                SomnaSegmented(options: ["Оценка сна", "Длительность"], selection: $outcomeIndex)
                Text(windows[windowIndex] == 7
                     ? "За 7 дней показываем только записи, без вывода о связи."
                     : "Сравниваем сопоставимые дни по выходным, окну сна и предыдущей ночи. Нужно минимум \(FactorInsight.minimumPerGroup) ночей в каждой группе.")
                    .font(SomnaFont.body(13))
                    .foregroundStyle(p.fg2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if ready.isEmpty {
                StateBlock(icon: "chart.bar.doc.horizontal", state: .neutral,
                           title: "Пока недостаточно данных",
                           what: windows[windowIndex] == 7
                               ? "Выберите 30 или 90 дней: неделя слишком коротка для проверки связи."
                               : "Связи появятся, когда наберётся по \(FactorInsight.minimumPerGroup) ночей в каждой группе и 8 сопоставимых пар.",
                           available: "Кофеин, тренировки, свет и шаги подтянутся из Здоровья, остальное — из журнала",
                           actionTitle: "Открыть журнал", actionIcon: "square.and.pencil") {
                    state.go(to: .journal)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Связи в ваших данных", trailing: "\(ready.count)")
                    VStack(spacing: 12) {
                        ForEach(ready) { insight in
                            FactorInsightCard(insight: insight, factor: factor(insight.factorID))
                        }
                    }
                }
            }

            if !waiting.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    GroupCaption(text: "Собираем данные")
                    GroupedList {
                        ForEach(Array(waiting.enumerated()), id: \.element.id) { index, insight in
                            MetricRow(state: .neutral, label: insight.title,
                                      sub: "С фактором \(insight.withCount) · без \(insight.withoutCount) · пары \(insight.pairCount)",
                                      value: "", showChevron: false, showDivider: index < waiting.count - 1)
                        }
                    }
                }
            }

            IconLine(systemImage: "info.circle",
                     text: "Связь не доказывает причину: в такие дни могло совпасть что-то ещё. Проверить гипотезу можно экспериментом в журнале.")
        }
        .somnaNavTitle("Факторы сна", mode: mode)
    }

    private func factor(_ id: String) -> JournalFactor? {
        store.snapshot.factors.first { $0.id == id }
    }
}

struct FactorInsightCard: View {
    @Environment(\.palette) private var p
    let insight: FactorInsight
    let factor: JournalFactor?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemImage: factor?.systemImage ?? "tag",
                         state: insight.isStable ? (insight.isUnfavourable ? .caution : .restore) : .neutral, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.title)
                        .font(SomnaFont.body(16, .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(summary)
                        .font(SomnaFont.body(14))
                        .foregroundStyle(p.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Text(insight.outcome.formatDifference(insight.difference ?? 0))
                    .displayStyle(22, tracking: -0.5)
            }
            HStack(spacing: 8) {
                StatusTag(text: insight.isStable ? "Устойчивая связь" : "Связь неустойчива",
                          state: insight.isStable ? (insight.isUnfavourable ? .caution : .restore) : .neutral)
                if let lo = insight.intervalLow, let hi = insight.intervalHigh {
                    Text("вероятно от \(insight.outcome.formatDifference(lo)) до \(insight.outcome.formatDifference(hi))")
                        .font(SomnaFont.body(12))
                        .foregroundStyle(p.fg3)
                }
            }
        }
        .card(padding: 18, radius: Radius.row)
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        let with = insight.medianWith.map(format) ?? "—"
        let without = insight.medianWithout.map(format) ?? "—"
        return "С фактором: \(with) · без: \(without) · \(insight.pairCount) сопоставимых пар"
    }

    private func format(_ v: Double) -> String {
        switch insight.outcome {
        case .score: "\(Int(v.rounded()))"
        case .asleep, .latency: Fmt.duration(v)
        case .energy: Fmt.number(v, digits: 1)
        }
    }
}
