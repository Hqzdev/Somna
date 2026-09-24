//
//  Recovery.swift
//  SomnaCore
//
//  Nightly vitals and personal-baseline signals. No composite recovery score.
//

import Foundation

nonisolated struct MetricBaseline: Codable, Hashable, Sendable {
    static let window = 28
    static let minimumCount = 14
    static let madScale = 1.4826

    var kind: QuantityKind
    var median: Double
    /// 1.4826 × MAD, never below a small floor so equal values do not divide by zero.
    var scale: Double
    var count: Int

    /// `values` are the previous measurements (oldest first); the latest 28 are used.
    static func compute(kind: QuantityKind, values: [Double]) -> MetricBaseline? {
        let recent = Array(values.suffix(window))
        guard recent.count >= minimumCount,
              let m = Stats.median(recent),
              let mad = Stats.medianAbsoluteDeviation(recent) else { return nil }
        let floor = max(abs(m) * 0.02, 0.1)
        return MetricBaseline(kind: kind, median: m, scale: max(madScale * mad, floor), count: recent.count)
    }

    /// Robust z-score of `value` (positive = above the personal median).
    func z(_ value: Double) -> Double {
        (value - median) / scale
    }
}

nonisolated struct VitalsBaselineKey: Hashable, Sendable {
    var sourceID: String
    var timeBand: Int
}

nonisolated struct NightVitals: Codable, Hashable, Sendable {
    var hrv: Double?
    var hrvSourceID: String?
    /// Four-hour band relative to sleep onset; avoids comparing early and late-night HRV.
    var hrvTimeBand: Int?
    var restingHeartRate: Double?
    var rhrSourceID: String?
    /// Six-hour local clock band of the daily resting-heart-rate sample.
    var rhrTimeBand: Int?
    var respiratoryRate: Double?
    var wristTemperature: Double?
    var oxygenSaturation: Double?
    var heartRate: NightHeartRate?

    static let empty = NightVitals()

    func value(_ kind: QuantityKind) -> Double? {
        switch kind {
        case .hrv: hrv
        case .restingHeartRate: restingHeartRate
        case .respiratoryRate: respiratoryRate
        case .wristTemperature: wristTemperature
        case .oxygenSaturation: oxygenSaturation
        default: nil
        }
    }

    /// Medians of samples recorded during the sleep period; resting heart
    /// rate is Health's daily value for the wake day (or the day before).
    static func compute(night: SleepNight,
                        samples: [QuantityKind: [QuantitySample]],
                        heartRate: NightHeartRate?) -> NightVitals {
        let s = night.sleepStart
        let e = night.sleepEnd
        func during(_ kind: QuantityKind) -> (Double?, String?, Int?) {
            let eligible = (samples[kind] ?? []).filter { $0.start >= s && $0.start <= e }
            let grouped = Dictionary(grouping: eligible, by: \.sourceID)
            guard let chosen = grouped.sorted(by: { a, b in
                a.value.count != b.value.count ? a.value.count > b.value.count : a.key < b.key
            }).first else { return (nil, nil, nil) }
            let offsets = chosen.value.map { max(0, $0.start.timeIntervalSince(s) / 3600) }
            let band = Stats.median(offsets).map { min(2, Int($0 / 4)) }
            return (Stats.median(chosen.value.map(\.value)), chosen.key, band)
        }
        func overlapping(_ kind: QuantityKind) -> Double? {
            let values = (samples[kind] ?? []).filter { $0.start < e && $0.end > s }.map(\.value)
            return Stats.median(values)
        }
        var rhr: Double?
        var rhrSource: String?
        var rhrBand: Int?
        let tz = night.timeZone
        let rhrSamples = samples[.restingHeartRate] ?? []
        for day in [night.dayKey, night.dayKey.adding(days: -1)] {
            let onDay = rhrSamples.filter { DayKey(date: $0.end, timeZone: tz) == day }
            if let latest = onDay.max(by: { $0.end < $1.end }) {
                rhr = latest.value
                rhrSource = latest.sourceID
                let hour = SomnaCalendar.gregorian(tz).component(.hour, from: latest.end)
                rhrBand = hour / 6
                break
            }
        }
        let hrv = during(.hrv)
        return NightVitals(hrv: hrv.0, hrvSourceID: hrv.1, hrvTimeBand: hrv.2,
                           restingHeartRate: rhr,
                           rhrSourceID: rhrSource, rhrTimeBand: rhrBand,
                           respiratoryRate: during(.respiratoryRate).0,
                           wristTemperature: overlapping(.wristTemperature),
                           oxygenSaturation: during(.oxygenSaturation).0,
                           heartRate: heartRate)
    }
}

nonisolated struct RecoveryReport: Codable, Hashable, Sendable {
    var asleepMinutes: Double
    var goalMinutes: Int
    /// Robust deviations from source- and time-matched personal baselines.
    var hrvDeviation: Double?
    var rhrDeviation: Double?
    var hrvBaseline: MetricBaseline?
    var rhrBaseline: MetricBaseline?
    var status: RecoveryStatus = .insufficient
    var signalCount: Int = 0
    var adverseCount: Int = 0

    var hasPhysiology: Bool { hrvDeviation != nil || rhrDeviation != nil }

    static func compute(asleepMinutes: Double, goalMinutes: Int,
                        vitals: NightVitals,
                        hrvBaseline: MetricBaseline?,
                        rhrBaseline: MetricBaseline?,
                        energy: Int? = nil) -> RecoveryReport {
        var hrvDeviation: Double?
        var rhrDeviation: Double?
        if let b = hrvBaseline, let v = vitals.hrv {
            hrvDeviation = b.z(v)
        }
        if let b = rhrBaseline, let v = vitals.restingHeartRate {
            rhrDeviation = b.z(v)
        }
        let count = 1 + (hrvDeviation == nil ? 0 : 1) + (rhrDeviation == nil ? 0 : 1) + (energy == nil ? 0 : 1)
        let adverse = (Double(goalMinutes) - asleepMinutes >= 60 ? 1 : 0)
            + ((hrvDeviation ?? 0) <= -1 ? 1 : 0)
            + ((rhrDeviation ?? 0) >= 1 ? 1 : 0)
            + ((energy ?? 5) <= 2 ? 1 : 0)
        let status: RecoveryStatus = count < 2 ? .insufficient : (adverse >= 2 ? .lowerThanUsual : (adverse == 0 ? .ordinary : .mixed))
        return RecoveryReport(asleepMinutes: asleepMinutes, goalMinutes: goalMinutes,
                              hrvDeviation: hrvDeviation,
                              rhrDeviation: rhrDeviation,
                              hrvBaseline: hrvDeviation == nil ? nil : hrvBaseline,
                              rhrBaseline: rhrDeviation == nil ? nil : rhrBaseline,
                              status: status, signalCount: count, adverseCount: adverse)
    }
}

nonisolated enum RecoveryStatus: String, Codable, Hashable, Sendable {
    case ordinary, lowerThanUsual, mixed, insufficient

    var title: String {
        switch self {
        case .ordinary: "Без заметных отклонений"
        case .lowerThanUsual: "Несколько сигналов отклоняются"
        case .mixed: "Показатели неоднозначны"
        case .insufficient: "Недостаточно данных"
        }
    }
}
