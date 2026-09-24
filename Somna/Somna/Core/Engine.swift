//
//  Engine.swift
//  SomnaCore
//
//  One pure function from everything the app knows to one snapshot every
//  screen reads: SomnaEngine.compute(SomnaInput) → SomnaSnapshot.
//  Changing the goal, a check-in, a journal entry or a source priority means
//  recomputing the snapshot; nothing on screen is stored separately.
//

import Foundation

nonisolated struct SomnaInput: Sendable {
    var sleepSamples: [SleepSample] = []
    var quantities: [QuantitySample] = []
    var workouts: [WorkoutSample] = []
    var heartRateByNight: [DayKey: NightHeartRate] = [:]
    var healthRefreshedAt: Date?
    var sourcePreferences: [SourcePreference] = []
    var profile: OnboardingProfile = .empty
    var settings: SleepSettings = .default
    var checkIns: [MorningCheckIn] = []
    var goalHistory: [GoalChange] = []
    var journal: [JournalEntry] = []
    var customFactors: [JournalFactor] = []
    var experiments: [Experiment] = []
    var now: Date = Date()
    var timeZone: TimeZone = .current

    init() {}
}

nonisolated struct NightReport: Sendable, Identifiable {
    var night: SleepNight
    var score: SleepScore?
    var goalMinutes: Int
    var scoreComponents: ScoreComponents
    var measurements: NightMeasurementReport
    var regularity: RegularityReport?
    var vitals: NightVitals
    var recovery: RecoveryReport?
    var checkIn: MorningCheckIn?
    /// Explanation of the score in plain Russian.
    var explanation: String?
    /// Comparable nights still missing before the score includes the rhythm (0 = included or not applicable).
    var rhythmNightsMissing: Int = 0

    var id: String { night.id }
    var dayKey: DayKey { night.dayKey }
}

nonisolated struct DetectedSource: Hashable, Sendable, Identifiable {
    var id: String
    var name: String
    var rank: Int
    var sampleCount: Int
    var hasStages: Bool
}

nonisolated enum DataState: Hashable, Sendable {
    /// No sleep records yet.
    case noData
    /// Fewer than 7 valid nights: numbers are preliminary.
    case collecting(nights: Int)
    case ready(nights: Int)

    var nights: Int {
        switch self {
        case .noData: 0
        case .collecting(let n), .ready(let n): n
        }
    }
}

nonisolated struct SomnaSnapshot: Sendable {
    static let formulaVersion = "v2"

    var generatedAt: Date
    var today: DayKey
    var timeZone: TimeZone
    var reports: [NightReport]
    var naps: [NapSummary]
    var dataState: DataState
    var balance: SleepBalance?
    var regularity: RegularityReport?
    var forecast: ForecastModel
    var factors: [JournalFactor]
    var factorValues: [String: [DayKey: Double]]
    var factorInsights: [FactorInsight]
    var experiments: [ExperimentReport]
    var trends: [TrendObservation]
    var plan: RecoveryPlan
    var needSuggestion: SleepNeedSuggestion?
    var sources: [DetectedSource]
    var settings: SleepSettings
    /// Wake time used by plan, forecast and alarm (minutes after midnight).
    var wakeMinutes: Int
    var outcomes: OutcomeTable
    /// Valid nights still missing before regularity is computed (0 = ready or not applicable).
    var regularityNightsMissing: Int = 0

    /// Latest night, if it ended today or yesterday.
    var latest: NightReport? {
        guard let last = reports.last, last.dayKey >= today.adding(days: -1) else { return nil }
        return last
    }

    var lastRecorded: NightReport? { reports.last }

    func report(for day: DayKey) -> NightReport? {
        reports.first { $0.dayKey == day }
    }

    func insights(window: Int, outcome: OutcomeMetric) -> [FactorInsight] {
        factorInsights.filter { $0.windowDays == window && $0.outcome == outcome }
    }

    static func empty(now: Date = Date(), timeZone: TimeZone = .current) -> SomnaSnapshot {
        var input = SomnaInput()
        input.now = now
        input.timeZone = timeZone
        return SomnaEngine.compute(input)
    }
}

nonisolated enum SomnaEngine {
    static let defaultWakeMinutes = 7 * 60 + 30

    static func compute(_ input: SomnaInput) -> SomnaSnapshot {
        let tz = input.timeZone
        let today = DayKey(date: input.now, timeZone: tz)
        let goal = input.settings.goalMinutes
        let goalHistory = input.goalHistory.sorted { $0.effectiveDay < $1.effectiveDay }
        func goalFor(_ day: DayKey) -> Int {
            goalHistory.last { $0.effectiveDay <= day }?.minutes ?? goal
        }
        let history = NightBuilder.build(samples: input.sleepSamples,
                                         preferences: input.sourcePreferences,
                                         defaultTimeZone: tz)
        let nights = history.nights.filter { $0.dayKey <= today }
        let checkIns = Dictionary(input.checkIns.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, b in b })
        let byKind = Dictionary(grouping: input.quantities, by: \.kind)

        // Per-night reports: regularity uses the nights up to that one,
        // baselines use the 28 nights before it.
        var reports: [NightReport] = []
        var validSoFar: [SleepNight] = []
        var hrvHistory: [VitalsBaselineKey: [Double]] = [:]
        var rhrHistory: [VitalsBaselineKey: [Double]] = [:]
        for night in nights {
            let vitals = NightVitals.compute(night: night, samples: byKind,
                                             heartRate: input.heartRateByNight[night.dayKey])
            var regularity: RegularityReport?
            var score: SleepScore?
            let shiftWork = input.profile.difficulties.contains(.shiftWork)
            let rhythm = RegularityReport.rhythm(for: night, previous: validSoFar, shiftWork: shiftWork)
            let rhythmMissing = rhythm == nil && !night.timeZoneChanged
                ? max(0, RegularityReport.minimumNights
                      - RegularityReport.comparable(for: night, previous: validSoFar, shiftWork: shiftWork).count)
                : 0
            let components = SleepScore.components(night: night, goalMinutes: goalFor(night.dayKey), rhythm: rhythm)
            let recovery = RecoveryReport.compute(asleepMinutes: night.asleepMinutes,
                                                  goalMinutes: goalFor(night.dayKey),
                                                  vitals: vitals,
                                                  hrvBaseline: baseline(.hrv, source: vitals.hrvSourceID,
                                                                        band: vitals.hrvTimeBand, history: hrvHistory),
                                                  rhrBaseline: baseline(.restingHeartRate, source: vitals.rhrSourceID,
                                                                        band: vitals.rhrTimeBand, history: rhrHistory),
                                                  energy: checkIns[night.dayKey]?.energy)
            if night.isValid {
                regularity = shiftWork ? nil : RegularityReport.compute(nights: validSoFar + [night])
            }
            if night.asleep > 0, let base = SleepScore.compute(components: components) {
                let comparable = reports.reversed().prefix { $0.night.primarySourceID == night.primarySourceID }
                let rated: [RatedNight] = comparable.reversed().compactMap { report in
                    guard report.night.isValid, report.score?.isPartial == false,
                          let baseScore = report.score?.baseValue,
                          let quality = report.checkIn?.quality else { return nil }
                    let coverage = report.night.detailedStageCoverage
                    return RatedNight(baseScore: Double(baseScore), perceivedQuality: quality,
                                      deepFraction: coverage >= 0.90 ? report.night.stages.deep / report.night.asleep : -1,
                                      remFraction: coverage >= 0.90 ? report.night.stages.rem / report.night.asleep : -1)
                }
                score = ScorePersonalizer.apply(base, night: night, previous: rated)
            }
            var report = NightReport(night: night, score: score, goalMinutes: goalFor(night.dayKey),
                                     scoreComponents: components, measurements: night.measurements.refreshed(at: input.healthRefreshedAt),
                                     regularity: regularity, vitals: vitals,
                                     recovery: recovery, checkIn: checkIns[night.dayKey])
            report.rhythmNightsMissing = rhythmMissing
            report.explanation = explain(report, goalMinutes: goalFor(night.dayKey))
            reports.append(report)
            if night.isValid {
                validSoFar.append(night)
                if let v = vitals.hrv, let source = vitals.hrvSourceID, let band = vitals.hrvTimeBand {
                    hrvHistory[VitalsBaselineKey(sourceID: source, timeBand: band), default: []].append(v)
                }
                if let v = vitals.restingHeartRate, let source = vitals.rhrSourceID, let band = vitals.rhrTimeBand {
                    rhrHistory[VitalsBaselineKey(sourceID: source, timeBand: band), default: []].append(v)
                }
            }
        }

        let validCount = validSoFar.count
        let dataState: DataState = nights.isEmpty ? .noData
            : (validCount < 7 ? .collecting(nights: validCount) : .ready(nights: validCount))
        let regularity = input.profile.difficulties.contains(.shiftWork) ? nil : RegularityReport.compute(nights: validSoFar)
        let balance = SleepBalance.compute(nights: nights, goalMinutes: goal, goalHistory: goalHistory, endDay: today)
        let forecast = ForecastModel.build(nights: validSoFar, goalMinutes: goal, regularity: regularity?.score)

        // Outcomes per night for factors and experiments.
        var outcomeValues: [OutcomeMetric: [DayKey: Double]] = [:]
        for r in reports where r.night.isValid {
            // Partial scores (no rhythm yet) are on a different scale: kept out of comparisons.
            if let s = r.score, !s.isPartial { outcomeValues[.score, default: [:]][r.dayKey] = Double(s.value) }
            outcomeValues[.asleep, default: [:]][r.dayKey] = r.night.asleepMinutes
            if let l = r.night.latencyMinutes { outcomeValues[.latency, default: [:]][r.dayKey] = l }
        }
        for c in input.checkIns {
            outcomeValues[.energy, default: [:]][c.dayKey] = Double(c.energy)
        }
        let asleepByDay = Dictionary(reports.map { ($0.dayKey, $0.night.asleepMinutes) }, uniquingKeysWith: { _, b in b })
        let opportunity = Dictionary(reports.compactMap { report -> (DayKey, Double)? in
            guard report.measurements.timeInBed.status == .measured else { return nil }
            return report.night.timeInBed.map { (report.dayKey, $0 / 60) }
        }, uniquingKeysWith: { _, b in b })
        let previousSleep = Dictionary(reports.compactMap { report -> (DayKey, Double)? in
            asleepByDay[report.dayKey.adding(days: -1)].map { (report.dayKey, $0) }
        }, uniquingKeysWith: { _, b in b })
        let outcomes = OutcomeTable(values: outcomeValues, sleepOpportunity: opportunity, previousSleep: previousSleep)

        let factors = FactorCatalog.all(custom: input.customFactors)
        let factorValues = FactorResolver.resolve(factors: factors,
                                                  journal: input.journal,
                                                  quantities: input.quantities,
                                                  workouts: input.workouts,
                                                  naps: history.naps,
                                                  nightDays: Set(nights.map(\.dayKey)),
                                                  timeZone: tz)
        let lastNightDay = validSoFar.last?.dayKey ?? today
        var insights: [FactorInsight] = []
        for factor in factors {
            let values = factorValues[factor.id] ?? [:]
            for window in FactorInsight.windows {
                for outcome in [OutcomeMetric.score, .asleep] {
                    insights.append(FactorAnalyzer.analyze(factor: factor, values: values, outcomes: outcomes,
                                                           outcome: outcome, endDay: lastNightDay, windowDays: window))
                }
            }
        }
        FactorAnalyzer.adjustFalseDiscovery(&insights)

        let experiments = input.experiments.map { ExperimentAnalyzer.analyze($0, outcomes: outcomes, today: today) }

        var series: [TrendMetric: [DayKey: Double]] = [:]
        for r in reports where r.night.isValid {
            series[.asleep, default: [:]][r.dayKey] = r.night.asleepMinutes
            series[.bedtime, default: [:]][r.dayKey] = r.night.bedtimeScale
            if let v = r.vitals.hrv { series[.hrv, default: [:]][r.dayKey] = v }
            if let v = r.vitals.restingHeartRate { series[.restingHeartRate, default: [:]][r.dayKey] = v }
            if let v = r.vitals.respiratoryRate { series[.respiratoryRate, default: [:]][r.dayKey] = v }
            if let v = r.vitals.wristTemperature { series[.wristTemperature, default: [:]][r.dayKey] = v }
            if let v = r.vitals.oxygenSaturation { series[.oxygenSaturation, default: [:]][r.dayKey] = v }
        }
        let trends = TrendMetric.allCases.compactMap { m in
            TrendAnalyzer.analyze(metric: m, series: series[m] ?? [:], endDay: lastNightDay)
        }

        let usualWake = regularity.map { Int($0.medianWake.rounded()) }
        let wakeMinutes = input.settings.wakeMinutes ?? usualWake.map(PlanBuilder.roundTo5) ?? defaultWakeMinutes
        let plan = PlanBuilder.build(day: today, settings: input.settings, wakeMinutes: wakeMinutes,
                                     profile: input.profile, regularity: regularity, forecast: forecast,
                                     insights: insights, factors: factors, nights: validCount)

        let need = SleepNeedSuggestion.compute(nights: validSoFar, checkIns: checkIns, currentGoal: goal)

        var sampleCounts: [String: (name: String, count: Int, stages: Bool)] = [:]
        for s in input.sleepSamples {
            var e = sampleCounts[s.sourceID] ?? (s.sourceName, 0, false)
            e.count += 1
            if s.stage.isDetailedStage { e.stages = true }
            sampleCounts[s.sourceID] = e
        }
        let sources = sampleCounts.map { id, e in
            DetectedSource(id: id, name: e.name, rank: history.sourceRanking[id] ?? Int.max,
                           sampleCount: e.count, hasStages: e.stages)
        }.sorted { $0.rank < $1.rank }

        var snapshot = SomnaSnapshot(generatedAt: input.now,
                             today: today,
                             timeZone: tz,
                             reports: reports,
                             naps: history.naps,
                             dataState: dataState,
                             balance: balance,
                             regularity: regularity,
                             forecast: forecast,
                             factors: factors,
                             factorValues: factorValues,
                             factorInsights: insights,
                             experiments: experiments,
                             trends: trends,
                             plan: plan,
                             needSuggestion: need,
                             sources: sources,
                             settings: input.settings,
                             wakeMinutes: wakeMinutes,
                             outcomes: outcomes)
        if regularity == nil && !input.profile.difficulties.contains(.shiftWork) {
            snapshot.regularityNightsMissing = max(0, RegularityReport.minimumNights
                                                   - RegularityReport.recent(nights: validSoFar).count)
        }
        return snapshot
    }

    private static func baseline(_ kind: QuantityKind, source: String?, band: Int?,
                                 history: [VitalsBaselineKey: [Double]]) -> MetricBaseline? {
        guard let source, let band else { return nil }
        return MetricBaseline.compute(kind: kind, values: history[VitalsBaselineKey(sourceID: source, timeBand: band)] ?? [])
    }

    /// Explain what was measured without implying a clinical assessment.
    static func explain(_ report: NightReport, goalMinutes: Int) -> String? {
        guard let score = report.score else {
            if report.scoreComponents.continuity == nil {
                return "Время сна записано, но источник не дал достаточно надёжных данных о засыпании и пробуждениях для общего балла."
            }
            return "Для общего балла не хватает данных этой ночи."
        }
        let night = report.night
        var parts: [(weight: Double, text: String)] = []
        let gap = Double(goalMinutes) - night.asleepMinutes
        if gap >= 10 {
            parts.append((gap, "Сна на \(CoreFormat.duration(minutes: gap)) меньше цели."))
        } else {
            parts.append((0, "Сна хватило: \(CoreFormat.duration(minutes: night.asleepMinutes)) при цели \(CoreFormat.duration(minutes: Double(goalMinutes)))."))
        }
        if let c = score.components.continuity, c < 85 {
            parts.append((100 - c, "Засыпание, ночное бодрствование или пробуждения повлияли на оценку непрерывности."))
        }
        if let r = score.components.regularity, r < 75 {
            parts.append(((75 - r) / 2, "Время этой ночи отличается от вашего недавнего режима."))
        }
        let top = parts.sorted { $0.weight > $1.weight }.prefix(2).map(\.text)
        var text = top.joined(separator: " ")
        if score.isPartial {
            if night.timeZoneChanged {
                text += " Режим не учтён: ночь в другом часовом поясе."
            } else if report.rhythmNightsMissing > 0 {
                text += " Режим пока не учтён — он добавится через \(CoreFormat.nights(report.rhythmNightsMissing))."
            }
        }
        return text
    }
}
