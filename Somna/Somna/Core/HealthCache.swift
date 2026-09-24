//
//  HealthCache.swift
//  SomnaCore
//
//  The minimal copy of Apple Health data needed to recompute results:
//  normalized samples keyed by their HealthKit UUID, so additions, edits
//  (same UUID) and deletions in Health are applied exactly. Anything older
//  than the history window is dropped. Apple Health remains the source of
//  truth; this cache can always be rebuilt from it.
//

import Foundation

nonisolated struct HealthCache: Codable, Sendable {
    static let schemaVersion = 1
    /// Factors and trends look back at most 90 days; keep a margin.
    static let historyDays = 120

    var version = HealthCache.schemaVersion
    var sleep: [String: SleepSample] = [:]
    var quantities: [String: QuantitySample] = [:]
    var workouts: [String: WorkoutSample] = [:]
    /// Heart rate during each night's main sleep (statistics, not raw samples).
    var heartRate: [String: NightHeartRate] = [:]
    /// Archived HealthKit query anchors by data type.
    var anchors: [String: Data] = [:]
    var lastSync: Date?

    init() {}

    var isEmpty: Bool { sleep.isEmpty && quantities.isEmpty && workouts.isEmpty }

    mutating func applySleep(added: [SleepSample], deleted: [String]) {
        for id in deleted { sleep[id] = nil }
        for s in added { sleep[s.id] = s }
    }

    mutating func applyQuantities(added: [QuantitySample], deleted: [String]) {
        for id in deleted { quantities[id] = nil }
        for q in added { quantities[q.id] = q }
    }

    mutating func applyWorkouts(added: [WorkoutSample], deleted: [String]) {
        for id in deleted { workouts[id] = nil }
        for w in added { workouts[w.id] = w }
    }

    /// Daily totals (steps, daylight) use one id per kind and day, so a newer
    /// total replaces the older one.
    mutating func upsertDailyTotals(_ totals: [QuantitySample]) {
        for t in totals { quantities[t.id] = t }
    }

    mutating func prune(before cutoff: Date) {
        sleep = sleep.filter { $0.value.end >= cutoff }
        quantities = quantities.filter { $0.value.end >= cutoff }
        workouts = workouts.filter { $0.value.end >= cutoff }
    }

    func heartRateByNight() -> [DayKey: NightHeartRate] {
        var out: [DayKey: NightHeartRate] = [:]
        for (k, v) in heartRate {
            if let d = DayKey(string: k) { out[d] = v }
        }
        return out
    }

    /// Fills a snapshot input with the cached Health data.
    func fill(_ input: inout SomnaInput) {
        input.sleepSamples = sleep.values.sorted { $0.start < $1.start }
        input.quantities = quantities.values.sorted { $0.start < $1.start }
        input.workouts = workouts.values.sorted { $0.start < $1.start }
        input.heartRateByNight = heartRateByNight()
        input.healthRefreshedAt = lastSync
    }

    /// Stable id for a daily total (one value per kind and day).
    static func dailyID(_ kind: QuantityKind, _ day: DayKey) -> String {
        "\(kind.rawValue)-\(day.description)"
    }
}
