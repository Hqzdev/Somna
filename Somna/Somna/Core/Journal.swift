//
//  Journal.swift
//  SomnaCore
//
//  Journal factors, morning check-ins and how a factor value for a day is
//  resolved: the journal wins, then data from Apple Health; anything else is
//  «unknown» — a missing factor is never guessed.
//
//  A factor logged on day D is compared with the night that ends on D + 1.
//

import Foundation

nonisolated enum FactorKind: String, Codable, Sendable {
    /// 0 = no, 1 = yes.
    case yesNo
    /// 1…5.
    case scale
    /// Count (drinks).
    case count
    /// Minutes (daylight).
    case minutes
    /// Steps.
    case steps
}

nonisolated enum JournalSection: String, Codable, Sendable, CaseIterable {
    case evening, night, day

    var title: String {
        switch self {
        case .evening: "Вечер"
        case .night: "Спальня"
        case .day: "День"
        }
    }
}

nonisolated struct JournalFactor: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var kind: FactorKind
    var systemImage: String
    var section: JournalSection
    /// «With factor» when the value is at least this.
    var threshold: Double
    /// Apple Health can fill the value on days without a journal entry.
    var healthDerived: Bool
    /// The plan may suggest skipping it when it is linked with worse sleep.
    var avoidable: Bool
    var isCustom: Bool

    init(id: String, title: String, kind: FactorKind, systemImage: String, section: JournalSection,
         threshold: Double = 1, healthDerived: Bool = false, avoidable: Bool = false, isCustom: Bool = false) {
        self.id = id
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
        self.section = section
        self.threshold = threshold
        self.healthDerived = healthDerived
        self.avoidable = avoidable
        self.isCustom = isCustom
    }

    func isPresent(_ value: Double) -> Bool { value >= threshold }
}

nonisolated struct JournalEntry: Codable, Hashable, Sendable {
    /// Day of the evening the factor belongs to.
    var dayKey: DayKey
    var factorID: String
    var value: Double

    init(dayKey: DayKey, factorID: String, value: Double) {
        self.dayKey = dayKey
        self.factorID = factorID
        self.value = value
    }
}

nonisolated struct MorningCheckIn: Codable, Hashable, Sendable {
    /// Wake day of the night being rated.
    var dayKey: DayKey
    /// 1…5.
    var energy: Int
    /// Optional perceived sleep quality, independent of the computed score.
    var quality: Int? = nil
    var tags: [String]
    var note: String

    init(dayKey: DayKey, energy: Int, quality: Int? = nil, tags: [String] = [], note: String = "") {
        self.dayKey = dayKey
        self.energy = min(5, max(1, energy))
        self.quality = quality.map { min(5, max(1, $0)) }
        self.tags = tags
        self.note = note
    }
}

nonisolated enum FactorCatalog {
    static let caffeineLate = "caffeineLate"
    static let alcohol = "alcohol"
    static let lateMeal = "lateMeal"
    static let screenInBed = "screenInBed"
    static let medication = "medication"
    static let stress = "stress"
    static let workout = "workout"
    static let lateWorkout = "lateWorkout"
    static let nap = "nap"
    static let daylight = "daylight"
    static let steps = "steps"
    static let roomHot = "roomHot"
    static let roomNoise = "roomNoise"
    static let roomLight = "roomLight"

    static let builtIn: [JournalFactor] = [
        JournalFactor(id: lateMeal, title: "Поздний ужин", kind: .yesNo, systemImage: "fork.knife",
                      section: .evening, avoidable: true),
        JournalFactor(id: alcohol, title: "Алкоголь", kind: .count, systemImage: "wineglass",
                      section: .evening, healthDerived: true, avoidable: true),
        JournalFactor(id: screenInBed, title: "Экран в кровати", kind: .yesNo, systemImage: "iphone",
                      section: .evening, avoidable: true),
        JournalFactor(id: lateWorkout, title: "Тренировка после 19:00", kind: .yesNo, systemImage: "figure.run",
                      section: .evening, healthDerived: true, avoidable: true),
        JournalFactor(id: medication, title: "Лекарства", kind: .yesNo, systemImage: "pills",
                      section: .evening),
        JournalFactor(id: roomHot, title: "Жарко в спальне", kind: .yesNo, systemImage: "thermometer.sun",
                      section: .night, avoidable: true),
        JournalFactor(id: roomNoise, title: "Шумно в спальне", kind: .yesNo, systemImage: "speaker.wave.2",
                      section: .night, avoidable: true),
        JournalFactor(id: roomLight, title: "Светло в спальне", kind: .yesNo, systemImage: "lightbulb",
                      section: .night, avoidable: true),
        JournalFactor(id: caffeineLate, title: "Кофеин после 14:00", kind: .yesNo, systemImage: "cup.and.saucer",
                      section: .day, healthDerived: true, avoidable: true),
        JournalFactor(id: stress, title: "Стресс", kind: .scale, systemImage: "bolt.heart",
                      section: .day, threshold: 4),
        JournalFactor(id: workout, title: "Тренировка", kind: .yesNo, systemImage: "figure.strengthtraining.traditional",
                      section: .day, healthDerived: true),
        JournalFactor(id: nap, title: "Дневной сон", kind: .yesNo, systemImage: "bed.double",
                      section: .day, healthDerived: true, avoidable: true),
        JournalFactor(id: daylight, title: "Дневной свет", kind: .minutes, systemImage: "sun.max",
                      section: .day, threshold: 30, healthDerived: true),
        JournalFactor(id: steps, title: "10 000 шагов", kind: .steps, systemImage: "figure.walk",
                      section: .day, threshold: 10_000, healthDerived: true)
    ]

    static func all(custom: [JournalFactor]) -> [JournalFactor] {
        builtIn + custom
    }
}

/// Health-derived factor values by day (journal entries are applied on top).
nonisolated enum FactorResolver {
    /// Evening cut-off for «late» caffeine.
    static let lateCaffeineMinutes = 14 * 60
    /// «Late» workout starts at or after 19:00.
    static let lateWorkoutMinutes = 19 * 60

    /// Returns factorID → (day → value). Missing days mean «unknown».
    static func resolve(factors: [JournalFactor],
                        journal: [JournalEntry],
                        quantities: [QuantitySample],
                        workouts: [WorkoutSample],
                        naps: [NapSummary],
                        nightDays: Set<DayKey>,
                        timeZone: TimeZone) -> [String: [DayKey: Double]] {
        var result: [String: [DayKey: Double]] = [:]
        let ids = Set(factors.map(\.id))

        // Caffeine after 14:00, alcohol, daylight and steps from Health.
        var caffeineDays: [DayKey: Double] = [:]
        var alcoholDays: [DayKey: Double] = [:]
        var daylightDays: [DayKey: Double] = [:]
        var stepDays: [DayKey: Double] = [:]
        for q in quantities {
            let day = DayKey(date: q.start, timeZone: timeZone)
            switch q.kind {
            case .caffeine:
                let late = ClockTime.minutesOfDay(q.start, in: timeZone) >= Double(lateCaffeineMinutes) && q.value > 0
                caffeineDays[day] = max(caffeineDays[day] ?? 0, late ? 1 : 0)
            case .alcoholicBeverages:
                alcoholDays[day, default: 0] += q.value
            case .daylight:
                daylightDays[day, default: 0] += q.value
            case .steps:
                stepDays[day, default: 0] += q.value
            default:
                break
            }
        }
        if ids.contains(FactorCatalog.caffeineLate) { result[FactorCatalog.caffeineLate] = caffeineDays }
        if ids.contains(FactorCatalog.alcohol) { result[FactorCatalog.alcohol] = alcoholDays }
        if ids.contains(FactorCatalog.daylight) { result[FactorCatalog.daylight] = daylightDays }
        if ids.contains(FactorCatalog.steps) { result[FactorCatalog.steps] = stepDays }

        // Workouts: when the person records workouts at all, a day without one
        // is «no workout» (from the first to the last recorded day ± 30 days).
        if !workouts.isEmpty {
            var any: [DayKey: Double] = [:]
            var late: [DayKey: Double] = [:]
            for w in workouts {
                let day = DayKey(date: w.start, timeZone: timeZone)
                any[day] = 1
                if ClockTime.minutesOfDay(w.start, in: timeZone) >= Double(lateWorkoutMinutes) {
                    late[day] = 1
                }
            }
            let workoutDays = any.keys.sorted()
            if let first = workoutDays.first, let last = workoutDays.last {
                var day = first.adding(days: -30)
                let end = last.adding(days: 30)
                while day <= end {
                    if any[day] == nil { any[day] = 0 }
                    if late[day] == nil { late[day] = 0 }
                    day = day.adding(days: 1)
                }
            }
            if ids.contains(FactorCatalog.workout) { result[FactorCatalog.workout] = any }
            if ids.contains(FactorCatalog.lateWorkout) { result[FactorCatalog.lateWorkout] = late }
        }

        // Naps: known only on days whose following night was recorded.
        if ids.contains(FactorCatalog.nap) {
            var napDays: [DayKey: Double] = [:]
            for day in nightDays {
                napDays[day.adding(days: -1)] = 0
            }
            for n in naps {
                napDays[n.dayKey] = 1
            }
            result[FactorCatalog.nap] = napDays
        }

        // The journal overrides Health.
        for e in journal where ids.contains(e.factorID) {
            result[e.factorID, default: [:]][e.dayKey] = e.value
        }
        return result
    }
}
