//
//  HealthKitReader.swift
//  Somna
//
//  Read-only access to Apple Health. Somna never writes to Health.
//
//  • Each data type is requested separately and only for reading; the
//    system sheet is shown in context (onboarding «Подключить Apple Health»).
//  • HealthKit does not tell an app whether reading was denied. No records
//    is shown as «данных пока нет», never as a proven refusal.
//  • Anchored queries return additions and deletions since the last sync,
//    so edits and removals in Health reach the local cache.
//

import Foundation
import HealthKit

nonisolated final class HealthKitReader: @unchecked Sendable {
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    let store = HKHealthStore()

    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let heartRateType = HKQuantityType(.heartRate)
    private let workoutType = HKObjectType.workoutType()

    /// Samples cached one by one (with their HealthKit UUID).
    private let sampledTypes: [(QuantityKind, HKQuantityType, HKUnit, Double)] = [
        (.hrv, HKQuantityType(.heartRateVariabilitySDNN), .secondUnit(with: .milli), 1),
        (.restingHeartRate, HKQuantityType(.restingHeartRate), HKUnit.count().unitDivided(by: .minute()), 1),
        (.respiratoryRate, HKQuantityType(.respiratoryRate), HKUnit.count().unitDivided(by: .minute()), 1),
        (.wristTemperature, HKQuantityType(.appleSleepingWristTemperature), .degreeCelsius(), 1),
        (.oxygenSaturation, HKQuantityType(.oxygenSaturation), .percent(), 100),
        (.caffeine, HKQuantityType(.dietaryCaffeine), .gramUnit(with: .milli), 1),
        (.alcoholicBeverages, HKQuantityType(.numberOfAlcoholicBeverages), .count(), 1)
    ]

    /// Cumulative types stored as one total per day (Health removes duplicates).
    private let dailyTypes: [(QuantityKind, HKQuantityType, HKUnit)] = [
        (.steps, HKQuantityType(.stepCount), .count()),
        (.daylight, HKQuantityType(.timeInDaylight), .minute())
    ]

    var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [sleepType, heartRateType, workoutType]
        for t in sampledTypes { types.insert(t.1) }
        for t in dailyTypes { types.insert(t.1) }
        return types
    }

    // MARK: Authorization

    /// Shows the system sheet (only the first time; later calls return at once).
    func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// True when the system sheet has not been shown yet for these types.
    func needsAuthorizationRequest() async -> Bool {
        guard Self.isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        return status == .shouldRequest
    }

    // MARK: Sleep

    func fetchSleep(anchor: HKQueryAnchor?, since: Date) async throws -> (added: [SleepSample], deleted: [String], anchor: HKQueryAnchor) {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.categorySample(type: sleepType, predicate: predicate)],
            anchor: anchor)
        let result = try await descriptor.result(for: store)
        return (result.addedSamples.compactMap(Self.sleepSample),
                result.deletedObjects.map { $0.uuid.uuidString },
                result.newAnchor)
    }

    static func sleepSample(_ s: HKCategorySample) -> SleepSample? {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: s.value) else { return nil }
        let stage: SleepStage
        switch value {
        case .inBed: stage = .inBed
        case .awake: stage = .awake
        case .asleepCore: stage = .core
        case .asleepDeep: stage = .deep
        case .asleepREM: stage = .rem
        case .asleepUnspecified: stage = .asleepUnspecified
        @unknown default: return nil
        }
        let source = s.sourceRevision.source
        return SleepSample(id: s.uuid.uuidString,
                           start: s.startDate,
                           end: s.endDate,
                           stage: stage,
                           sourceID: source.bundleIdentifier,
                           sourceName: source.name,
                           timeZoneID: s.metadata?[HKMetadataKeyTimeZone] as? String)
    }

    // MARK: Quantities

    /// Kinds fetched sample by sample, with their anchor keys.
    var sampledKinds: [QuantityKind] { sampledTypes.map(\.0) }

    func fetchQuantities(kind: QuantityKind, anchor: HKQueryAnchor?, since: Date) async throws
        -> (added: [QuantitySample], deleted: [String], anchor: HKQueryAnchor) {
        guard let entry = sampledTypes.first(where: { $0.0 == kind }) else {
            throw HealthReadError.unsupported
        }
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.quantitySample(type: entry.1, predicate: predicate)],
            anchor: anchor)
        let result = try await descriptor.result(for: store)
        let added = result.addedSamples.map { s in
            QuantitySample(id: s.uuid.uuidString,
                           kind: kind,
                           start: s.startDate,
                           end: s.endDate,
                           value: s.quantity.doubleValue(for: entry.2) * entry.3,
                           sourceID: s.sourceRevision.source.bundleIdentifier)
        }
        return (added, result.deletedObjects.map { $0.uuid.uuidString }, result.newAnchor)
    }

    /// One total per local day for steps and daylight.
    func fetchDailyTotals(since: Date, until: Date, timeZone: TimeZone) async throws -> [QuantitySample] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: since)
        var out: [QuantitySample] = []
        for (kind, type, unit) in dailyTypes {
            let descriptor = HKStatisticsCollectionQueryDescriptor(
                predicate: .quantitySample(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: until)),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1))
            let collection = try await descriptor.result(for: store)
            for stats in collection.statistics() {
                guard let sum = stats.sumQuantity() else { continue }
                let day = DayKey(date: stats.startDate, timeZone: timeZone)
                out.append(QuantitySample(id: HealthCache.dailyID(kind, day), kind: kind,
                                          start: stats.startDate, end: stats.endDate,
                                          value: sum.doubleValue(for: unit)))
            }
        }
        return out
    }

    // MARK: Heart rate during sleep

    /// Average and minimum heart rate between sleep start and wake, plus a
    /// 15-minute average series for the night chart.
    func nightHeartRate(from start: Date, to end: Date) async throws -> NightHeartRate? {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let summary = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: heartRateType, predicate: predicate),
            options: [.discreteAverage, .discreteMin])
        guard let stats = try await summary.result(for: store),
              let average = stats.averageQuantity()?.doubleValue(for: bpm),
              let minimum = stats.minimumQuantity()?.doubleValue(for: bpm) else { return nil }

        let seriesQuery = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: heartRateType, predicate: predicate),
            options: .discreteAverage,
            anchorDate: start,
            intervalComponents: DateComponents(minute: NightHeartRate.seriesStepMinutes))
        var series: [Double?] = []
        if let collection = try? await seriesQuery.result(for: store) {
            collection.enumerateStatistics(from: start, to: end) { stats, _ in
                series.append(stats.averageQuantity()?.doubleValue(for: bpm))
            }
        }
        var result = NightHeartRate(average: average, minimum: minimum)
        result.series = series
        result.seriesStart = start
        return result
    }

    // MARK: Workouts

    func fetchWorkouts(anchor: HKQueryAnchor?, since: Date) async throws -> (added: [WorkoutSample], deleted: [String], anchor: HKQueryAnchor) {
        let predicate = HKQuery.predicateForSamples(withStart: since, end: nil)
        let descriptor = HKAnchoredObjectQueryDescriptor(
            predicates: [.workout(predicate)],
            anchor: anchor)
        let result = try await descriptor.result(for: store)
        let added = result.addedSamples.map { w in
            WorkoutSample(id: w.uuid.uuidString, start: w.startDate, end: w.endDate,
                          activityName: Self.name(of: w.workoutActivityType))
        }
        return (added, result.deletedObjects.map { $0.uuid.uuidString }, result.newAnchor)
    }

    static func name(of type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Бег"
        case .walking: "Ходьба"
        case .hiking: "Поход"
        case .cycling: "Велосипед"
        case .swimming: "Плавание"
        case .yoga: "Йога"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Силовая"
        case .highIntensityIntervalTraining: "Интервальная"
        case .dance: "Танцы"
        default: "Тренировка"
        }
    }

    // MARK: Updates while the app runs

    /// Calls `onChange` when new sleep records arrive. Returns the query so it
    /// can be stopped.
    func observeSleep(onChange: @escaping @Sendable () -> Void) -> HKObserverQuery {
        let query = HKObserverQuery(sampleType: sleepType, predicate: nil) { _, completion, error in
            if error == nil { onChange() }
            completion()
        }
        store.execute(query)
        return query
    }

    // MARK: Anchors

    static func archive(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}

nonisolated enum HealthReadError: Error {
    case unsupported
}
