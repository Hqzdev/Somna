//
//  Insights.swift
//  SomnaCore
//
//  Factors, experiments and long-term trends (v1). Everything here is an
//  association in the person's own data, never a cause and never a diagnosis.
//

import Foundation

/// What a factor or an experiment is compared on.
nonisolated enum OutcomeMetric: String, Codable, Sendable, CaseIterable {
    case score
    case asleep
    case latency
    case energy

    var title: String {
        switch self {
        case .score: "Оценка сна"
        case .asleep: "Длительность сна"
        case .latency: "Время засыпания"
        case .energy: "Утренняя энергия"
        }
    }

    /// For latency, lower is better.
    var higherIsBetter: Bool { self != .latency }

    /// Formats a difference in this metric's unit.
    func formatDifference(_ value: Double) -> String {
        switch self {
        case .score:
            let v = Int(value.rounded())
            return v > 0 ? "+\(v)" : (v < 0 ? "−\(-v)" : "0")
        case .asleep, .latency:
            return CoreFormat.signedMinutes(value)
        case .energy:
            let v = (value * 10).rounded() / 10
            let text = String(format: "%.1f", abs(v)).replacingOccurrences(of: ".", with: ",")
            return v > 0 ? "+\(text)" : (v < 0 ? "−\(text)" : "0")
        }
    }
}

/// Per-night outcome values, keyed by the night's wake day.
nonisolated struct OutcomeTable: Sendable {
    var values: [OutcomeMetric: [DayKey: Double]]
    var sleepOpportunity: [DayKey: Double] = [:]
    var previousSleep: [DayKey: Double] = [:]

    func value(_ metric: OutcomeMetric, _ day: DayKey) -> Double? {
        values[metric]?[day]
    }
}

// MARK: - Factors

nonisolated struct FactorInsight: Codable, Hashable, Sendable, Identifiable {
    static let windows = [7, 30, 90]
    static let minimumPerGroup = 10

    var factorID: String
    var title: String
    var windowDays: Int
    var outcome: OutcomeMetric
    var withCount: Int
    var withoutCount: Int
    var medianWith: Double?
    var medianWithout: Double?
    /// median(with) − median(without).
    var difference: Double?
    /// 80 % bootstrap interval of the difference.
    var intervalLow: Double?
    var intervalHigh: Double?
    var pairCount: Int = 0
    var pValue: Double? = nil
    var qValue: Double? = nil

    var id: String { "\(factorID)|\(windowDays)|\(outcome.rawValue)" }

    var hasEnoughData: Bool {
        windowDays >= 30 && withCount >= Self.minimumPerGroup && withoutCount >= Self.minimumPerGroup
            && pairCount >= 8 && difference != nil
    }

    /// The interval does not cross zero: the link held up in this person's data.
    var isStable: Bool {
        guard hasEnoughData, let lo = intervalLow, let hi = intervalHigh,
              let qValue, qValue <= 0.10 else { return false }
        return lo > 0 || hi < 0
    }

    /// True when nights with the factor were worse for sleep.
    var isUnfavourable: Bool {
        guard let d = difference else { return false }
        return outcome.higherIsBetter ? d < 0 : d > 0
    }
}

nonisolated enum FactorAnalyzer {
    private struct Observation {
        var day: DayKey
        var result: Double
        var opportunity: Double
        var previousSleep: Double
        var weekend: Bool
    }

    /// Compares nights after days with the factor against nights after days
    /// without it, within `windowDays` nights ending at `endDay`.
    static func analyze(factor: JournalFactor,
                        values: [DayKey: Double],
                        outcomes: OutcomeTable,
                        outcome: OutcomeMetric,
                        endDay: DayKey,
                        windowDays: Int) -> FactorInsight {
        var with: [Observation] = []
        var without: [Observation] = []
        let firstNight = endDay.adding(days: -(windowDays - 1))
        for (factorDay, v) in values {
            let nightDay = factorDay.adding(days: 1)
            guard nightDay >= firstNight, nightDay <= endDay,
                  let result = outcomes.value(outcome, nightDay) else { continue }
            guard let opportunity = outcomes.sleepOpportunity[nightDay],
                  let previous = outcomes.previousSleep[nightDay] else { continue }
            let weekday = SomnaCalendar.utc.component(.weekday,
                from: nightDay.date(atMinutes: 12 * 60, in: SomnaCalendar.utcZone))
            let item = Observation(day: nightDay, result: result, opportunity: opportunity,
                                   previousSleep: previous, weekend: weekday == 1 || weekday == 7)
            if factor.isPresent(v) { with.append(item) } else { without.append(item) }
        }
        var insight = FactorInsight(factorID: factor.id, title: factor.title, windowDays: windowDays,
                                    outcome: outcome, withCount: with.count, withoutCount: without.count)
        guard windowDays >= 30, with.count >= FactorInsight.minimumPerGroup,
              without.count >= FactorInsight.minimumPerGroup else { return insight }
        var unused = without
        var differences: [Double] = []
        var pairedWith: [Double] = []
        var pairedWithout: [Double] = []
        for item in with.sorted(by: { $0.day < $1.day }) {
            let candidates = unused.enumerated().filter { _, candidate in
                candidate.weekend == item.weekend
                    && abs(candidate.opportunity - item.opportunity) <= 60
                    && abs(candidate.previousSleep - item.previousSleep) <= 90
                    && abs(candidate.day.days(to: item.day)) <= 30
            }
            guard let chosen = candidates.min(by: { abs($0.element.day.days(to: item.day)) < abs($1.element.day.days(to: item.day)) }) else { continue }
            let control = unused.remove(at: chosen.offset)
            pairedWith.append(item.result)
            pairedWithout.append(control.result)
            differences.append(item.result - control.result)
        }
        insight.pairCount = differences.count
        guard differences.count >= 8 else { return insight }
        insight.medianWith = Stats.median(pairedWith)
        insight.medianWithout = Stats.median(pairedWithout)
        insight.difference = Stats.median(differences)
        if let interval = Stats.bootstrapMedian(differences, seed: Stats.stableHash(insight.id)) {
            insight.intervalLow = interval.low
            insight.intervalHigh = interval.high
        }
        insight.pValue = Stats.signTestTwoSided(differences)
        return insight
    }

    static func adjustFalseDiscovery(_ insights: inout [FactorInsight]) {
        // One family of all displayed tests; selecting a favourable outcome
        // or time window must not escape the multiple-testing correction.
        let ranked = insights.indices.filter { insights[$0].pValue != nil }
            .sorted { (insights[$0].pValue ?? 1) < (insights[$1].pValue ?? 1) }
        var next = 1.0
        for position in ranked.indices.reversed() {
            let index = ranked[position]
            let raw = (insights[index].pValue ?? 1) * Double(ranked.count) / Double(position + 1)
            next = min(next, raw)
            insights[index].qValue = next
        }
    }
}

// MARK: - Experiments

nonisolated enum ExperimentStatus: String, Codable, Sendable {
    case active, stopped, finished
}

nonisolated struct Experiment: Codable, Hashable, Sendable, Identifiable {
    static let baselineDays = 14
    static let durationDays = 14
    static let minimumBaselineNights = 10
    static let minimumExperimentNights = 10

    var id: String
    var title: String
    var detail: String
    var metric: OutcomeMetric
    /// First evening with the new habit.
    var startDay: DayKey
    var status: ExperimentStatus
    /// Evenings the habit was done (the person's own marks).
    var doneDays: [DayKey]

    init(id: String, title: String, detail: String, metric: OutcomeMetric, startDay: DayKey,
         status: ExperimentStatus = .active, doneDays: [DayKey] = []) {
        self.id = id
        self.title = title
        self.detail = detail
        self.metric = metric
        self.startDay = startDay
        self.status = status
        self.doneDays = doneDays
    }

    /// Nights before the habit: wake days startDay − 13 … startDay.
    var baselineNightDays: ClosedRange<DayKey> {
        startDay.adding(days: -(Self.baselineDays - 1))...startDay
    }

    /// Nights with the habit: wake days startDay + 1 … startDay + 14.
    var experimentNightDays: ClosedRange<DayKey> {
        startDay.adding(days: 1)...startDay.adding(days: Self.durationDays)
    }
}

nonisolated struct ExperimentReport: Hashable, Sendable, Identifiable {
    var experiment: Experiment
    var baselineCount: Int
    var experimentCount: Int
    var adherenceCount: Int = 0
    var baselineMedian: Double?
    var experimentMedian: Double?
    /// experiment − baseline.
    var difference: Double?
    var intervalLow: Double?
    var intervalHigh: Double?
    /// Days since the start (1 = the first night with the habit).
    var dayNumber: Int
    var isComplete: Bool

    var id: String { experiment.id }

    /// Comparable calendar days and sufficient adherence are required.
    var isInterpretable: Bool {
        baselineCount >= Experiment.minimumBaselineNights
            && experimentCount >= Experiment.minimumExperimentNights
            && adherenceCount >= Experiment.minimumExperimentNights
            && difference != nil
    }

    var isImprovement: Bool {
        guard let d = difference else { return false }
        return experiment.metric.higherIsBetter ? d > 0 : d < 0
    }
}

nonisolated enum ExperimentAnalyzer {
    static func analyze(_ experiment: Experiment, outcomes: OutcomeTable, today: DayKey) -> ExperimentReport {
        let metric = experiment.metric
        let upTo = min(experiment.experimentNightDays.upperBound, today)
        var baseline: [Double] = []
        var during: [Double] = []
        var differences: [Double] = []
        let doneDays = Set(experiment.doneDays)
        var pairedAdherence = 0
        if upTo >= experiment.experimentNightDays.lowerBound {
            var day = experiment.experimentNightDays.lowerBound
            while day <= upTo {
                if let current = outcomes.value(metric, day),
                   let prior = outcomes.value(metric, day.adding(days: -14)) {
                    baseline.append(prior)
                    during.append(current)
                    differences.append(current - prior)
                    if doneDays.contains(day.adding(days: -1)) { pairedAdherence += 1 }
                }
                day = day.adding(days: 1)
            }
        }
        var report = ExperimentReport(experiment: experiment,
                                      baselineCount: baseline.count,
                                      experimentCount: during.count,
                                      adherenceCount: pairedAdherence,
                                      dayNumber: max(0, min(Experiment.durationDays, experiment.startDay.days(to: today))),
                                      isComplete: today >= experiment.experimentNightDays.upperBound)
        if let b = Stats.median(baseline), let e = Stats.median(during), let d = Stats.median(differences) {
            report.baselineMedian = b
            report.experimentMedian = e
            report.difference = d
            if let ci = Stats.bootstrapMedian(differences, seed: Stats.stableHash(experiment.id)) {
                report.intervalLow = ci.low
                report.intervalHigh = ci.high
            }
        }
        return report
    }

}

// MARK: - Trends

nonisolated enum TrendMetric: String, Codable, Sendable, CaseIterable {
    case asleep
    case bedtime
    case hrv
    case restingHeartRate
    case respiratoryRate
    case wristTemperature
    case oxygenSaturation

    var title: String {
        switch self {
        case .asleep: "Длительность сна"
        case .bedtime: "Время засыпания"
        case .hrv: "Вариабельность пульса"
        case .restingHeartRate: "Пульс в покое"
        case .respiratoryRate: "Частота дыхания"
        case .wristTemperature: "Температура запястья"
        case .oxygenSaturation: "Кислород в крови"
        }
    }

    var unit: String {
        switch self {
        case .asleep, .bedtime: "мин"
        case .hrv: "мс"
        case .restingHeartRate: "уд/мин"
        case .respiratoryRate: "вд/мин"
        case .wristTemperature: "°C"
        case .oxygenSaturation: "%"
        }
    }
}

nonisolated struct TrendObservation: Codable, Hashable, Sendable, Identifiable {
    static let recentDays = 7
    static let priorDays = 28
    static let minimumRecent = 5
    static let minimumPrior = 14
    static let sustainedZ = 1.5

    var metric: TrendMetric
    var recentMedian: Double
    var priorMedian: Double
    var difference: Double
    var z: Double
    var recentCount: Int
    var priorCount: Int
    /// |z| ≥ 1.5 and at least 5 of the last 7 values on the same side.
    var isSustained: Bool

    var id: String { metric.rawValue }
    var isUp: Bool { difference > 0 }
}

nonisolated enum TrendAnalyzer {
    /// Median of the last 7 nights against the previous 28 nights.
    static func analyze(metric: TrendMetric, series: [DayKey: Double], endDay: DayKey) -> TrendObservation? {
        let recentStart = endDay.adding(days: -(TrendObservation.recentDays - 1))
        let priorEnd = recentStart.adding(days: -1)
        let priorStart = priorEnd.adding(days: -(TrendObservation.priorDays - 1))
        let recent = series.filter { $0.key >= recentStart && $0.key <= endDay }.map(\.value)
        let prior = series.filter { $0.key >= priorStart && $0.key <= priorEnd }.map(\.value)
        guard recent.count >= TrendObservation.minimumRecent,
              prior.count >= TrendObservation.minimumPrior,
              let rm = Stats.median(recent), let pm = Stats.median(prior),
              let mad = Stats.medianAbsoluteDeviation(prior) else { return nil }
        let scale = max(MetricBaseline.madScale * mad, max(abs(pm) * 0.02, 0.1))
        let diff = rm - pm
        let z = diff / scale
        let sameSide = recent.filter { diff >= 0 ? $0 > pm : $0 < pm }.count
        return TrendObservation(metric: metric, recentMedian: rm, priorMedian: pm, difference: diff, z: z,
                                recentCount: recent.count, priorCount: prior.count,
                                isSustained: abs(z) >= TrendObservation.sustainedZ && sameSide >= TrendObservation.minimumRecent)
    }
}
