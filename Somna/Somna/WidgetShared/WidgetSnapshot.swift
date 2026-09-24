//
//  WidgetSnapshot.swift
//  Somna + SomnaWidgets
//
//  What the iPhone widgets show. The app computes it with SomnaCore after
//  every recompute and stores it in the App Group; the widget extension only
//  lays it out and never touches Health data or the formulas.
//
//  Plan times are stored as minutes after the plan day's midnight, so a
//  widget can re-project them onto tonight even when the app was not opened.
//

import Foundation

nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let groupID = "group.yaroslavstrelkov.Somna"
    static let storageKey = "widgetSnapshot.v1"
    static let kind = "SomnaWidget"
    static let clockKind = "SomnaClockWidget"

    var generatedAt: Date
    var timeZoneID: String
    var isOnboarded: Bool
    /// Latest night, if it ended today or yesterday.
    var night: Night?
    /// Shortfall to the sleep goal over 14 days.
    var shortfall: Shortfall?
    var plan: Plan?

    nonisolated struct Night: Codable, Equatable, Sendable {
        var sleepStart: Date
        var sleepEnd: Date
        var asleepMinutes: Int
        var goalMinutes: Int
        var score: Int?
        var scoreLabel: String?
        /// Median score of the previous 30 nights (needs at least 7).
        var norm: Int?
        /// Short recovery status: «как обычно», «ниже обычного», «неоднозначно».
        var recovery: String?
        var sourceName: String?
        var syncedAt: Date?
        /// Minutes per stage when the source recorded detailed stages.
        var stages: Stages?
        /// Hypnogram, as fractions of sleepStart…sleepEnd.
        var segments: [Segment]
    }

    nonisolated struct Stages: Codable, Equatable, Sendable {
        var deep: Int
        var core: Int
        var rem: Int
        var awake: Int
    }

    nonisolated enum Stage: String, Codable, Sendable {
        case awake, rem, core, deep, asleep
    }

    nonisolated struct Segment: Codable, Equatable, Sendable {
        var start: Double
        var end: Double
        var stage: Stage
    }

    nonisolated struct Shortfall: Codable, Equatable, Sendable {
        var minutes: Int
        var isPreliminary: Bool
    }

    nonisolated struct Plan: Codable, Equatable, Sendable {
        /// Plan day, "yyyy-MM-dd".
        var day: String
        /// Minutes after the plan day's midnight (may exceed 1440).
        var bedtimeMinutes: Int
        /// Minutes after midnight of the next morning.
        var wakeMinutes: Int
        /// Start of the screen-free wind-down, when the plan has one.
        var windDownMinutes: Int?
        var predictedSleepMinutes: Int?
        /// Goal minus predicted sleep: positive means the shortfall grows.
        var balanceChangeMinutes: Int?
        var alarmEnabled: Bool
        var steps: [Step]
    }

    nonisolated struct Step: Codable, Equatable, Sendable, Identifiable {
        var id: String
        /// «Режим без экрана»
        var title: String
        /// «без экрана» — for the lock screen.
        var short: String
        /// Minutes after the plan day's midnight.
        var minutes: Int?
        var systemImage: String
        var status: StepStatus
    }

    nonisolated enum StepStatus: String, Codable, Sendable {
        case pending, done, skipped
    }

    static let empty = WidgetSnapshot(generatedAt: .distantPast,
                                      timeZoneID: TimeZone.current.identifier,
                                      isOnboarded: false,
                                      night: nil,
                                      shortfall: nil,
                                      plan: nil)
}

nonisolated enum WidgetSnapshotStore {
    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: WidgetSnapshot.groupID)?.data(forKey: WidgetSnapshot.storageKey),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    /// Stores the snapshot; returns true when what the widgets show changed
    /// (the generation time alone does not count).
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) -> Bool {
        guard let defaults = UserDefaults(suiteName: WidgetSnapshot.groupID) else { return false }
        var previous = load()
        previous.generatedAt = snapshot.generatedAt
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: WidgetSnapshot.storageKey)
        return previous != snapshot
    }
}
