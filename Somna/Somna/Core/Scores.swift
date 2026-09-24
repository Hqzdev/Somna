import Foundation

/// Product indicators, never a clinical assessment. Rolling comparisons use past nights only.
nonisolated struct RegularityReport: Codable, Hashable, Sendable {
    static let window = 14
    static let minimumNights = 7
    var nights: Int
    var bedtimeMAD: Double
    var wakeMAD: Double
    var combinedMAD: Double
    var score: Double
    var medianBedtime: Double
    var medianWake: Double
    var isPreliminary: Bool { nights < Self.window }

    /// Valid, comparable nights of the two weeks ending with the latest one.
    static func recent(nights: [SleepNight]) -> [SleepNight] {
        guard let last = nights.last else { return [] }
        let first = last.dayKey.adding(days: -(window - 1))
        return nights.filter {
            $0.isValid && $0.dayKey >= first && $0.dayKey <= last.dayKey
                && !$0.timeZoneChanged && $0.timeZoneID == last.timeZoneID
                && $0.primarySourceID == last.primarySourceID
        }
    }

    static func compute(nights: [SleepNight]) -> RegularityReport? {
        let recent = Self.recent(nights: nights)
        guard recent.count >= minimumNights else { return nil }
        let beds = recent.map(\.bedtimeScale)
        let wakes = recent.map(\.wakeScale)
        guard let bedMAD = Stats.meanAbsoluteDeviationFromMedian(beds),
              let wakeMAD = Stats.meanAbsoluteDeviationFromMedian(wakes),
              let medBed = Stats.median(beds), let medWake = Stats.median(wakes) else { return nil }
        let combined = (bedMAD + wakeMAD) / 2
        return RegularityReport(nights: recent.count, bedtimeMAD: bedMAD, wakeMAD: wakeMAD,
                                combinedMAD: combined, score: SleepScore.rhythmPoints(combined),
                                medianBedtime: medBed, medianWake: medWake)
    }

    /// Earlier nights this night's rhythm is compared with.
    static func comparable(for night: SleepNight, previous: [SleepNight], shiftWork: Bool = false) -> [SleepNight] {
        let first = night.dayKey.adding(days: -window)
        return previous.filter {
            $0.isValid && !$0.timeZoneChanged && $0.dayKey >= first && $0.dayKey < night.dayKey
                && $0.timeZoneID == night.timeZoneID && $0.primarySourceID == night.primarySourceID
                && (!shiftWork || (abs($0.bedtimeScale - night.bedtimeScale) <= 90
                                    && abs($0.wakeScale - night.wakeScale) <= 90))
        }
    }

    static func rhythm(for night: SleepNight, previous: [SleepNight], shiftWork: Bool = false) -> Double? {
        guard !night.timeZoneChanged else { return nil }
        let comparable = Self.comparable(for: night, previous: previous, shiftWork: shiftWork)
        guard comparable.count >= minimumNights,
              let bed = Stats.median(comparable.map(\.bedtimeScale)),
              let wake = Stats.median(comparable.map(\.wakeScale)) else { return nil }
        let deviation = (abs(night.bedtimeScale - bed) + abs(night.wakeScale - wake)) / 2
        return SleepScore.rhythmPoints(deviation)
    }
}

nonisolated struct ScoreComponents: Codable, Hashable, Sendable {
    var duration: Double? = nil
    var efficiency: Double? = nil // Informational; not weighted again.
    var regularity: Double? = nil
    var continuity: Double? = nil
    var latency: Double? = nil
    var wakeAfterOnset: Double? = nil
    var awakenings: Double? = nil
}

nonisolated struct SleepScore: Codable, Hashable, Sendable {
    var value: Int
    var components: ScoreComponents
    var isPersonalized: Bool = false
    var baseValue: Int? = nil

    /// Scored without the rhythm component: fewer than 7 comparable nights so far.
    var isPartial: Bool { components.regularity == nil }

    static func points(_ value: Double, anchors: [(Double, Double)]) -> Double {
        guard let first = anchors.first, let last = anchors.last else { return 0 }
        if value <= first.0 { return first.1 }
        if value >= last.0 { return last.1 }
        for pair in zip(anchors, anchors.dropFirst()) where value <= pair.1.0 {
            let fraction = (value - pair.0.0) / (pair.1.0 - pair.0.0)
            return pair.0.1 + fraction * (pair.1.1 - pair.0.1)
        }
        return last.1
    }

    static func durationComponent(asleepMinutes: Double, goalMinutes: Int) -> Double {
        let deficit = max(0, Double(goalMinutes) - asleepMinutes)
        return points(deficit, anchors: [(0, 100), (30, 85), (60, 65), (120, 25), (180, 0)])
    }

    static func rhythmPoints(_ deviation: Double) -> Double {
        points(deviation, anchors: [(30, 100), (60, 80), (120, 50), (240, 0)])
    }

    static func components(night: SleepNight, goalMinutes: Int, rhythm: Double?) -> ScoreComponents {
        var result = ScoreComponents(duration: durationComponent(asleepMinutes: night.asleepMinutes, goalMinutes: goalMinutes),
                                     efficiency: night.efficiency.map { $0 * 100 }, regularity: rhythm)
        guard night.continuityIsReliable, let latency = night.latencyMinutes else { return result }
        let onset = points(latency, anchors: [(30, 100), (90, 0)])
        let wake = points(night.awake / 60, anchors: [(20, 100), (100, 0)])
        let count = points(Double(night.awakeningsOverFiveMinutes), anchors: [(1, 100), (5, 0)])
        result.latency = onset
        result.wakeAfterOnset = wake
        result.awakenings = count
        result.continuity = 0.4 * onset + 0.4 * wake + 0.2 * count
        return result
    }

    static func compute(components c: ScoreComponents) -> SleepScore? {
        guard let duration = c.duration, let continuity = c.continuity else { return nil }
        let weighted: Double
        if let rhythm = c.regularity {
            weighted = 0.45 * duration + 0.45 * continuity + 0.10 * rhythm
        } else {
            // First nights: the rhythm baseline needs 7 comparable nights. Its 10 %
            // is left out and the rest re-weighted, not guessed.
            weighted = 0.5 * duration + 0.5 * continuity
        }
        let capped = min(weighted, min(duration, continuity) + 25)
        let value = Int(Stats.clamp(capped, 0, 100).rounded())
        return SleepScore(value: value, components: c, baseValue: value)
    }

    static func compute(night: SleepNight, goalMinutes: Int, regularity: RegularityReport?) -> SleepScore? {
        compute(components: components(night: night, goalMinutes: goalMinutes, rhythm: regularity?.score))
    }

    var label: String { Self.label(for: value) }
    static func label(for value: Int) -> String {
        switch value {
        case 85...: "Хорошие показатели"
        case 70..<85: "В целом спокойно"
        case 55..<70: "Есть что улучшить"
        default: "Ночь была непростой"
        }
    }
}

nonisolated struct RatedNight: Sendable {
    var baseScore: Double
    var perceivedQuality: Int
    var deepFraction: Double
    var remFraction: Double
}

/// Fit only on earlier nights. A failed holdout check returns the unmodified score.
nonisolated enum ScorePersonalizer {
    static func apply(_ score: SleepScore, night: SleepNight, previous: [RatedNight]) -> SleepScore {
        func target(_ pair: RatedNight) -> Double { Double(pair.perceivedQuality) * 20 }
        func error(_ items: [RatedNight], _ slope: Double, _ shift: Double) -> Double {
            items.reduce(0) { partial, item in
                partial + abs(target(item) - calibrated(item.baseScore, slope: slope, shift: shift))
            } / Double(items.count)
        }
        var adjusted = score
        var calibration = (slope: 1.0, shift: 0.0)
        if previous.count >= 60 {
            let pairs = Array(previous.suffix(60))
            if Set(pairs.map(\.perceivedQuality)).count >= 3 {
                let training = Array(pairs.prefix(40))
                let holdout = Array(pairs.suffix(20))
                var best = (slope: 1.0, shift: 0.0, error: Double.infinity)
                for slopeIndex in 15...25 {
                    for shift in -10...10 {
                        let slope = Double(slopeIndex) / 20
                        let loss = error(training, slope, Double(shift))
                        if loss < best.error { best = (slope, Double(shift), loss) }
                    }
                }
                let baselineError = error(holdout, 1, 0)
                if baselineError > 0, error(holdout, best.slope, best.shift) <= baselineError * 0.90 {
                    calibration = (best.slope, best.shift)
                    let base = Double(score.baseValue ?? score.value)
                    adjusted.value = Int(calibrated(base, slope: best.slope, shift: best.shift).rounded())
                    adjusted.isPersonalized = true
                }
            }
        }

        // Stage shares are allowed to make only a small, separately validated correction.
        let stagePairs = previous.filter { $0.deepFraction >= 0 && $0.remFraction >= 0 }
        if stagePairs.count >= 90, night.detailedStageCoverage >= 0.90, night.asleep > 0 {
            let stageTrain = Array(stagePairs.suffix(90).prefix(70))
            let stageHoldout = Array(stagePairs.suffix(20))
            let meanDeep = Stats.mean(stageTrain.map(\.deepFraction)) ?? 0
            let meanREM = Stats.mean(stageTrain.map(\.remFraction)) ?? 0
            let x = stageTrain.map { ($0.deepFraction - meanDeep) * 10 }
            let y = stageTrain.map { ($0.remFraction - meanREM) * 10 }
            let residual = stageTrain.map { target($0) - calibrated($0.baseScore, slope: calibration.slope, shift: calibration.shift) }
            let xx = zip(x, x).reduce(20.0) { $0 + $1.0 * $1.1 }
            let yy = zip(y, y).reduce(20.0) { $0 + $1.0 * $1.1 }
            let xy = zip(x, y).reduce(0.0) { $0 + $1.0 * $1.1 }
            let xr = zip(x, residual).reduce(0.0) { $0 + $1.0 * $1.1 }
            let yr = zip(y, residual).reduce(0.0) { $0 + $1.0 * $1.1 }
            let determinant = xx * yy - xy * xy
            if determinant > 0 {
                let deepCoefficient = (xr * yy - yr * xy) / determinant
                let remCoefficient = (yr * xx - xr * xy) / determinant
                func stageAdjustment(_ pair: RatedNight) -> Double {
                    Stats.clamp(deepCoefficient * (pair.deepFraction - meanDeep) * 10
                                + remCoefficient * (pair.remFraction - meanREM) * 10, -5, 5)
                }
                let withStage = stageHoldout.reduce(0.0) { $0 + abs(target($1) - calibrated($1.baseScore, slope: calibration.slope, shift: calibration.shift) - stageAdjustment($1)) } / 20
                let withoutStage = error(stageHoldout, calibration.slope, calibration.shift)
                if withoutStage > 0, withStage <= withoutStage * 0.90 {
                    let current = RatedNight(baseScore: Double(score.baseValue ?? score.value), perceivedQuality: 0,
                                             deepFraction: night.stages.deep / night.asleep,
                                             remFraction: night.stages.rem / night.asleep)
                    adjusted.value = Int(Stats.clamp(Double(adjusted.value) + stageAdjustment(current), 0, 100).rounded())
                    adjusted.isPersonalized = true
                }
            }
        }
        return adjusted
    }

    private static func calibrated(_ base: Double, slope: Double, shift: Double) -> Double {
        Stats.clamp(Stats.clamp(base * slope + shift, base - 10, base + 10), 0, 100)
    }
}

nonisolated struct GoalChange: Codable, Hashable, Sendable {
    var effectiveDay: DayKey
    var minutes: Int
}

nonisolated struct BalanceEntry: Codable, Hashable, Sendable {
    var dayKey: DayKey
    var asleepMinutes: Double
    var goalMinutes: Int
    var differenceMinutes: Double
}

/// Measured shortfall relative to a chosen target, not physiological debt.
nonisolated struct SleepBalance: Codable, Hashable, Sendable {
    static let window = 14
    static let minimumCoverage = 10
    var entries: [BalanceEntry]
    var goalMinutes: Int
    var availableDays: Int
    var nights: Int { entries.count }
    var hasCoverage: Bool { availableDays >= Self.minimumCoverage }
    var shortfallMinutes: Double { entries.reduce(0) { $0 + max(0, $1.differenceMinutes) } }
    var extraMinutes: Double { entries.reduce(0) { $0 + max(0, -$1.differenceMinutes) } }
    var deficitMinutes: Double { shortfallMinutes }
    var netMinutes: Double { shortfallMinutes - extraMinutes }
    var isPreliminary: Bool { !hasCoverage }

    static func compute(nights: [SleepNight], goalMinutes: Int, goalHistory: [GoalChange] = [], endDay: DayKey? = nil) -> SleepBalance? {
        guard let lastDay = endDay ?? nights.last?.dayKey else { return nil }
        let first = lastDay.adding(days: -(window - 1))
        // A confirmed short main sleep is still an observed day of shortfall;
        // only personal baselines exclude it.
        let recent = nights.filter { $0.asleep > 0 && $0.dayKey >= first && $0.dayKey <= lastDay }
        guard !recent.isEmpty else { return nil }
        let sortedGoals = goalHistory.sorted { $0.effectiveDay < $1.effectiveDay }
        let entries = recent.map { night -> BalanceEntry in
            let goal = sortedGoals.last { $0.effectiveDay <= night.dayKey }?.minutes ?? goalMinutes
            return BalanceEntry(dayKey: night.dayKey, asleepMinutes: night.asleepMinutes,
                                goalMinutes: goal, differenceMinutes: Double(goal) - night.asleepMinutes)
        }
        return SleepBalance(entries: entries, goalMinutes: goalMinutes, availableDays: recent.count)
    }
}

nonisolated struct SleepNeedSuggestion: Codable, Hashable, Sendable {
    static let window = 45
    static let minimumRated = 21
    static let minimumGood = 12
    var suggestedMinutes: Int
    var basedOnNights: Int

    static func compute(nights: [SleepNight], checkIns: [DayKey: MorningCheckIn], currentGoal: Int) -> SleepNeedSuggestion? {
        let recent = nights.filter(\.isValid).suffix(window)
        let rated = recent.filter { checkIns[$0.dayKey]?.quality != nil }
        guard rated.count >= minimumRated else { return nil }
        let good = rated.filter { (checkIns[$0.dayKey]?.quality ?? 0) >= 4 && (checkIns[$0.dayKey]?.energy ?? 0) >= 4 }
            .map(\.asleepMinutes)
        guard good.count >= minimumGood, let median = Stats.median(good),
              let low = Stats.quantile(good, 0.25), let high = Stats.quantile(good, 0.75),
              high - low <= 45 else { return nil }
        let rounded = Int((median / 15).rounded()) * 15
        guard abs(rounded - currentGoal) >= 15 else { return nil }
        return SleepNeedSuggestion(suggestedMinutes: min(11 * 60, max(5 * 60, rounded)), basedOnNights: good.count)
    }
}
