import Foundation

nonisolated struct SleepForecast: Hashable, Sendable {
    var windowMinutes: Double
    var predictedMinutes: Double?
    var lowMinutes: Double?
    var highMinutes: Double?
    var balanceChangeMinutes: Double?
    var latencyKnown: Bool
}

/// Robust forecast of time asleep, calibrated with rolling-origin residuals.
nonisolated struct ForecastModel: Codable, Hashable, Sendable {
    static let minimumNights = 30
    static let window = 28
    static let backtestNights = 60
    static let minimumBacktests = 20

    var nights: Int
    var goalMinutes: Int
    var medianLatency: Double?
    var medianAwake: Double?
    var medianEfficiency: Double?
    var regularity: Double?
    var medianLoss: Double?
    var planningLoss: Double?
    var historicalLowWindow: Double?
    var historicalHighWindow: Double?
    var errorLow: Double?
    var errorHigh: Double?

    var canPredict: Bool {
        nights >= Self.minimumNights && medianLoss != nil && errorLow != nil && errorHigh != nil
    }
    static let empty = ForecastModel(nights: 0, goalMinutes: SleepSettings.defaultGoalMinutes)

    init(nights: Int, goalMinutes: Int, medianLatency: Double? = nil, medianAwake: Double? = nil,
         medianEfficiency: Double? = nil, regularity: Double? = nil, medianLoss: Double? = nil,
         planningLoss: Double? = nil, historicalLowWindow: Double? = nil,
         historicalHighWindow: Double? = nil, errorLow: Double? = nil, errorHigh: Double? = nil) {
        self.nights = nights
        self.goalMinutes = goalMinutes
        self.medianLatency = medianLatency
        self.medianAwake = medianAwake
        self.medianEfficiency = medianEfficiency
        self.regularity = regularity
        self.medianLoss = medianLoss
        self.planningLoss = planningLoss
        self.historicalLowWindow = historicalLowWindow
        self.historicalHighWindow = historicalHighWindow
        self.errorLow = errorLow
        self.errorHigh = errorHigh
    }

    static func build(nights: [SleepNight], goalMinutes: Int, regularity: Double?) -> ForecastModel {
        guard let latest = nights.last else { return .empty }
        let first = latest.dayKey.adding(days: -45)
        let source = latest.primarySourceID
        let eligible = nights.filter {
            $0.isValid && $0.continuityIsReliable && $0.primarySourceID == source
                && $0.dayKey >= first && $0.timeInBed != nil
        }
        let recent = Array(eligible.suffix(window))
        let losses = recent.compactMap { night in night.timeInBed.map { max(0, $0 / 60 - night.asleepMinutes) } }
        let windows = recent.compactMap { $0.timeInBed.map { $0 / 60 } }
        var model = ForecastModel(nights: eligible.count, goalMinutes: goalMinutes,
                                  medianLatency: Stats.median(recent.compactMap(\.latencyMinutes)),
                                  medianAwake: Stats.median(recent.map { $0.awake / 60 }),
                                  medianEfficiency: Stats.median(recent.compactMap(\.efficiency)),
                                  regularity: regularity,
                                  medianLoss: Stats.median(losses),
                                  planningLoss: Stats.quantile(losses, 0.75),
                                  historicalLowWindow: Stats.quantile(windows, 0.1),
                                  historicalHighWindow: Stats.quantile(windows, 0.9))
        guard eligible.count >= minimumNights else { return model }
        var errors: [Double] = []
        for i in max(10, eligible.count - backtestNights)..<eligible.count {
            let past = Array(eligible[max(0, i - window)..<i])
            let pastLoss = past.compactMap { night in night.timeInBed.map { max(0, $0 / 60 - night.asleepMinutes) } }
            guard let loss = Stats.median(pastLoss), let targetWindow = eligible[i].timeInBed.map({ $0 / 60 }) else { continue }
            let prediction = max(0, targetWindow - loss)
            errors.append(eligible[i].asleepMinutes - prediction)
        }
        if errors.count >= minimumBacktests {
            model.errorLow = Stats.quantile(errors, 0.1)
            model.errorHigh = Stats.quantile(errors, 0.9)
        }
        return model
    }

    func predict(windowMinutes: Double) -> Double? {
        guard canPredict, let loss = medianLoss,
              let low = historicalLowWindow, let high = historicalHighWindow,
              windowMinutes >= low - 60, windowMinutes <= high + 60 else { return nil }
        return max(0, windowMinutes - loss)
    }

    func forecast(bedtime: Date, wake: Date) -> SleepForecast {
        let span = max(0, wake.timeIntervalSince(bedtime) / 60)
        let predicted = predict(windowMinutes: span)
        let low = predicted.flatMap { p in errorLow.map { max(0, min(p, p + $0)) } }
        let high = predicted.flatMap { p in errorHigh.map { min(span, max(p, p + $0)) } }
        return SleepForecast(windowMinutes: span, predictedMinutes: predicted,
                             lowMinutes: low, highMinutes: high,
                             balanceChangeMinutes: predicted.map { Double(goalMinutes) - $0 },
                             latencyKnown: medianLatency != nil)
    }
}
