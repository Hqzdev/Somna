//
//  SleepData.swift
//  SomnaCore
//
//  Normalized inputs. Apple Health stays the source of truth; these are the
//  minimal copies the app caches to recompute results (with their HealthKit
//  UUID, source and time zone), so edits and deletions in Health can be
//  applied.
//

import Foundation

/// HKCategoryValueSleepAnalysis, without HealthKit.
nonisolated enum SleepStage: String, Codable, Sendable, CaseIterable {
    case inBed
    case awake
    case asleepUnspecified
    case core
    case deep
    case rem

    var isAsleep: Bool {
        switch self {
        case .asleepUnspecified, .core, .deep, .rem: true
        case .inBed, .awake: false
        }
    }

    /// Core, deep or REM — a stage the source actually measured.
    var isDetailedStage: Bool {
        switch self {
        case .core, .deep, .rem: true
        default: false
        }
    }

    /// Which sample wins inside one source when they overlap.
    var specificity: Int {
        switch self {
        case .core, .deep, .rem: 3
        case .awake: 2
        case .asleepUnspecified: 1
        case .inBed: 0
        }
    }
}

nonisolated struct SleepSample: Codable, Hashable, Sendable, Identifiable {
    /// HealthKit UUID string.
    var id: String
    var start: Date
    var end: Date
    var stage: SleepStage
    /// Source bundle identifier (or another stable id).
    var sourceID: String
    var sourceName: String
    /// HKMetadataKeyTimeZone when the source wrote it.
    var timeZoneID: String?

    init(id: String, start: Date, end: Date, stage: SleepStage,
         sourceID: String, sourceName: String, timeZoneID: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.stage = stage
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.timeZoneID = timeZoneID
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// A painted piece of the night after duplicates were resolved.
nonisolated struct SleepInterval: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
    var stage: SleepStage
    var sourceID: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// User-chosen order of sources (lower `priority` wins overlaps).
nonisolated struct SourcePreference: Codable, Hashable, Sendable, Identifiable {
    var sourceID: String
    var name: String
    var priority: Int

    var id: String { sourceID }

    init(sourceID: String, name: String, priority: Int) {
        self.sourceID = sourceID
        self.name = name
        self.priority = priority
    }
}

/// Physiological measurements cached from Health.
nonisolated enum QuantityKind: String, Codable, Sendable, CaseIterable {
    /// Heart rate variability, SDNN, ms.
    case hrv
    /// Resting heart rate, bpm (one value a day).
    case restingHeartRate
    /// Breaths per minute.
    case respiratoryRate
    /// Sleeping wrist temperature, °C.
    case wristTemperature
    /// Blood oxygen, percent 0–100.
    case oxygenSaturation
    /// Dietary caffeine, mg.
    case caffeine
    /// Alcoholic drinks, count.
    case alcoholicBeverages
    /// Time in daylight, minutes.
    case daylight
    /// Steps (daily total).
    case steps
}

nonisolated struct QuantitySample: Codable, Hashable, Sendable, Identifiable {
    /// HealthKit UUID string (or "<kind>-<day>" for daily totals).
    var id: String
    var kind: QuantityKind
    var start: Date
    var end: Date
    var value: Double
    var sourceID: String

    init(id: String, kind: QuantityKind, start: Date, end: Date, value: Double, sourceID: String = "") {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.value = value
        self.sourceID = sourceID
    }
}

nonisolated struct WorkoutSample: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var start: Date
    var end: Date
    var activityName: String

    init(id: String, start: Date, end: Date, activityName: String) {
        self.id = id
        self.start = start
        self.end = end
        self.activityName = activityName
    }
}

/// Heart rate during the main sleep, from Health statistics queries.
nonisolated struct NightHeartRate: Codable, Hashable, Sendable {
    static let seriesStepMinutes = 15

    var average: Double
    var minimum: Double
    /// 15-minute averages from sleep start (nil where no measurement).
    var series: [Double?] = []
    var seriesStart: Date?

    init(average: Double, minimum: Double) {
        self.average = average
        self.minimum = minimum
    }
}
