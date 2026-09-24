//
//  SomnaRecords.swift
//  Somna
//
//  SwiftData records: what the person entered or decided (questionnaire,
//  settings, check-ins, journal, plan marks, experiments, source order) and
//  the computed nightly summaries. Everything stays on this iPhone —
//  no CloudKit, no account.
//

import Foundation
import SwiftData

@Model
final class ProfileRecord {
    var name: String = ""
    var goals: [String] = []
    var difficulties: [String] = []
    var note: String = ""
    var isCompleted: Bool = false
    var goalMinutes: Int = SleepSettings.defaultGoalMinutes
    /// Latest wake-up time; -1 = use the usual wake time.
    var wakeMinutes: Int = -1
    var alarmEnabled: Bool = false
    var alarmID: String = ""
    /// Wake time the current alarm was scheduled for; -1 = none.
    var alarmMinutes: Int = -1
    var hapticsEnabled: Bool = true
    /// The system Health sheet was shown at least once.
    var healthRequested: Bool = false
    var demoData: Bool = false
    var createdAt: Date = Date()

    init() {}

    var profile: OnboardingProfile {
        get {
            var p = OnboardingProfile()
            p.name = name
            p.goals = Set(goals.compactMap(SleepGoal.init(rawValue:)))
            p.difficulties = Set(difficulties.compactMap(SleepDifficulty.init(rawValue:)))
            p.note = note
            p.isCompleted = isCompleted
            return p
        }
        set {
            name = newValue.name
            goals = newValue.orderedGoals.map(\.rawValue)
            difficulties = newValue.orderedDifficulties.map(\.rawValue)
            note = newValue.note
            isCompleted = newValue.isCompleted
        }
    }

    var settings: SleepSettings {
        get {
            SleepSettings(goalMinutes: goalMinutes, wakeMinutes: wakeMinutes >= 0 ? wakeMinutes : nil,
                          alarmEnabled: alarmEnabled, hapticsEnabled: hapticsEnabled)
        }
        set {
            goalMinutes = newValue.goalMinutes
            wakeMinutes = newValue.wakeMinutes ?? -1
            alarmEnabled = newValue.alarmEnabled
            hapticsEnabled = newValue.hapticsEnabled
        }
    }
}

@Model
final class CheckInRecord {
    @Attribute(.unique) var day: String
    var energy: Int
    var quality: Int? = nil
    var tags: [String]
    var note: String
    var updatedAt: Date

    init(day: String, energy: Int, quality: Int? = nil, tags: [String], note: String) {
        self.day = day
        self.energy = energy
        self.quality = quality
        self.tags = tags
        self.note = note
        self.updatedAt = Date()
    }
}

@Model
final class GoalChangeRecord {
    @Attribute(.unique) var day: String
    var minutes: Int

    init(day: String, minutes: Int) {
        self.day = day
        self.minutes = minutes
    }
}

@Model
final class JournalRecord {
    /// "yyyy-MM-dd|factorID".
    @Attribute(.unique) var key: String
    var day: String
    var factorID: String
    var value: Double
    var updatedAt: Date

    init(day: String, factorID: String, value: Double) {
        self.key = "\(day)|\(factorID)"
        self.day = day
        self.factorID = factorID
        self.value = value
        self.updatedAt = Date()
    }
}

@Model
final class CustomFactorRecord {
    @Attribute(.unique) var id: String
    var title: String
    var kind: String
    var createdAt: Date

    init(id: String, title: String, kind: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.createdAt = Date()
    }
}

@Model
final class ExperimentRecord {
    @Attribute(.unique) var id: String
    var title: String
    var detail: String
    var metric: String
    var startDay: String
    var status: String
    var doneDays: [String]
    var createdAt: Date

    init(id: String, title: String, detail: String, metric: String, startDay: String, status: String) {
        self.id = id
        self.title = title
        self.detail = detail
        self.metric = metric
        self.startDay = startDay
        self.status = status
        self.doneDays = []
        self.createdAt = Date()
    }
}

@Model
final class SourcePreferenceRecord {
    @Attribute(.unique) var sourceID: String
    var name: String
    var priority: Int

    init(sourceID: String, name: String, priority: Int) {
        self.sourceID = sourceID
        self.name = name
        self.priority = priority
    }
}

/// The evening plan as it was shown, with the person's marks.
@Model
final class PlanRecord {
    @Attribute(.unique) var day: String
    /// JSON of [PlanAction].
    var actionsData: Data
    /// JSON of [actionID: status].
    var statusesData: Data
    var updatedAt: Date

    init(day: String, actionsData: Data, statusesData: Data) {
        self.day = day
        self.actionsData = actionsData
        self.statusesData = statusesData
        self.updatedAt = Date()
    }
}

/// Computed result of one night (formula version included), for history and export.
@Model
final class NightSummaryRecord {
    @Attribute(.unique) var day: String
    var formulaVersion: String
    var sleepStart: Date
    var sleepEnd: Date
    var asleepMinutes: Double
    var awakeMinutes: Double
    var timeInBedMinutes: Double
    var efficiency: Double
    var score: Int
    var durationScore: Double = -1
    var continuityScore: Double = -1
    var rhythmScore: Double = -1
    var scoreUnavailableReason: String = ""
    var recovery: Int
    var recoveryStatus: String = ""
    var hrv: Double
    var restingHeartRate: Double
    var sources: [String]
    var updatedAt: Date

    init(report: NightReport) {
        day = report.dayKey.description
        formulaVersion = SomnaSnapshot.formulaVersion
        sleepStart = report.night.sleepStart
        sleepEnd = report.night.sleepEnd
        asleepMinutes = report.night.asleepMinutes
        awakeMinutes = report.night.awake / 60
        timeInBedMinutes = (report.night.timeInBed ?? 0) / 60
        efficiency = report.night.efficiency ?? -1
        score = report.score?.value ?? -1
        durationScore = report.scoreComponents.duration ?? -1
        continuityScore = report.scoreComponents.continuity ?? -1
        rhythmScore = report.scoreComponents.regularity ?? -1
        scoreUnavailableReason = report.score == nil ? (report.explanation ?? "") : ""
        recovery = -1 // Legacy numeric column; v2 uses recoveryStatus.
        recoveryStatus = report.recovery?.status.rawValue ?? ""
        hrv = report.vitals.hrv ?? -1
        restingHeartRate = report.vitals.restingHeartRate ?? -1
        sources = report.night.sourceIDs
        updatedAt = Date()
    }

    func update(from report: NightReport) {
        formulaVersion = SomnaSnapshot.formulaVersion
        sleepStart = report.night.sleepStart
        sleepEnd = report.night.sleepEnd
        asleepMinutes = report.night.asleepMinutes
        awakeMinutes = report.night.awake / 60
        timeInBedMinutes = (report.night.timeInBed ?? 0) / 60
        efficiency = report.night.efficiency ?? -1
        score = report.score?.value ?? -1
        durationScore = report.scoreComponents.duration ?? -1
        continuityScore = report.scoreComponents.continuity ?? -1
        rhythmScore = report.scoreComponents.regularity ?? -1
        scoreUnavailableReason = report.score == nil ? (report.explanation ?? "") : ""
        recovery = -1
        recoveryStatus = report.recovery?.status.rawValue ?? ""
        hrv = report.vitals.hrv ?? -1
        restingHeartRate = report.vitals.restingHeartRate ?? -1
        sources = report.night.sourceIDs
        updatedAt = Date()
    }
}

enum SomnaSchema {
    static let models: [any PersistentModel.Type] = [
        ProfileRecord.self, CheckInRecord.self, GoalChangeRecord.self, JournalRecord.self, CustomFactorRecord.self,
        ExperimentRecord.self, SourcePreferenceRecord.self, PlanRecord.self, NightSummaryRecord.self
    ]

    /// On-device store in Application Support; no CloudKit.
    static func makeContainer() throws -> ModelContainer {
        let schema = Schema(models)
        let url = URL.applicationSupportDirectory.appending(path: "Somna", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema,
                                        url: url.appending(path: "Somna.store"),
                                        cloudKitDatabase: .none)
        // Never hide a migration or storage failure by silently starting with
        // an empty in-memory profile: personal notes and check-ins must remain intact.
        return try ModelContainer(for: schema, configurations: [config])
    }
}
