//
//  Profile.swift
//  SomnaCore
//
//  The start questionnaire (name, sleep goals, what gets in the way) and the
//  sleep settings the formulas use. A self-description, not a medical
//  assessment. Stored only on this iPhone — no account, no sync, no network.
//

import Foundation

// MARK: - Answer options

nonisolated enum SleepGoal: String, CaseIterable, Identifiable, Sendable {
    case fallAsleepFaster
    case wakeRested
    case regularSchedule
    case sleepLonger
    case fewerAwakenings
    case calmEvening

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fallAsleepFaster: "Быстрее засыпать"
        case .wakeRested: "Просыпаться бодрым"
        case .regularSchedule: "Ровный режим"
        case .sleepLonger: "Высыпаться"
        case .fewerAwakenings: "Реже просыпаться ночью"
        case .calmEvening: "Спокойный вечер"
        }
    }

    var subtitle: String {
        switch self {
        case .fallAsleepFaster: "Меньше ворочаться перед сном"
        case .wakeRested: "Без тяжести и разбитости по утрам"
        case .regularSchedule: "Ложиться и вставать в одно время"
        case .sleepLonger: "Добирать свою норму сна"
        case .fewerAwakenings: "Спать без долгих пробуждений"
        case .calmEvening: "Меньше экрана и мыслей перед сном"
        }
    }

    var systemImage: String {
        switch self {
        case .fallAsleepFaster: "moon.zzz"
        case .wakeRested: "sun.max"
        case .regularSchedule: "clock"
        case .sleepLonger: "bed.double"
        case .fewerAwakenings: "moon.stars"
        case .calmEvening: "leaf"
        }
    }
}

nonisolated enum SleepDifficulty: String, CaseIterable, Identifiable, Sendable {
    case slowToFallAsleep
    case nightWaking
    case earlyWaking
    case lateBedtime
    case phoneInBed
    case irregularSchedule
    case racingThoughts
    case daytimeSleepiness
    case noiseOrLight
    case lateCaffeine
    case shiftWork

    var id: String { rawValue }

    var title: String {
        switch self {
        case .slowToFallAsleep: "Долго засыпаю"
        case .nightWaking: "Просыпаюсь ночью"
        case .earlyWaking: "Просыпаюсь слишком рано"
        case .lateBedtime: "Поздно ложусь"
        case .phoneInBed: "Телефон в кровати"
        case .irregularSchedule: "Плавающий режим"
        case .racingThoughts: "Мысли и стресс"
        case .daytimeSleepiness: "Сонливость днём"
        case .noiseOrLight: "Шум или свет"
        case .lateCaffeine: "Кофеин вечером"
        case .shiftWork: "Работаю посменно"
        }
    }
}

// MARK: - Profile

nonisolated struct OnboardingProfile: Equatable, Sendable {
    static let nameLimit = 40
    static let noteLimit = 120

    var name: String = ""
    var goals: Set<SleepGoal> = []
    var difficulties: Set<SleepDifficulty> = []
    /// Optional free text for «Другое».
    var note: String = ""
    var isCompleted = false

    static let empty = OnboardingProfile()

    /// Trimmed name, or nil when the step was skipped.
    var displayName: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNote: String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// At least one goal is required to finish the questionnaire.
    var hasGoals: Bool { !goals.isEmpty }

    /// Goals in catalogue order, for stable display.
    var orderedGoals: [SleepGoal] { SleepGoal.allCases.filter { goals.contains($0) } }
    var orderedDifficulties: [SleepDifficulty] { SleepDifficulty.allCases.filter { difficulties.contains($0) } }

    var goalsSummary: String {
        orderedGoals.isEmpty ? "Не выбраны" : orderedGoals.map(\.title).joined(separator: ", ")
    }

    var difficultiesSummary: String {
        var items = orderedDifficulties.map(\.title)
        if let trimmedNote { items.append("другое: \(trimmedNote)") }
        return items.isEmpty ? "Не отмечены" : items.joined(separator: ", ")
    }

    /// Cleaned copy that is safe to store.
    func normalized(completed: Bool) -> OnboardingProfile {
        var copy = self
        copy.name = String((displayName ?? "").prefix(Self.nameLimit))
        copy.note = String((trimmedNote ?? "").prefix(Self.noteLimit))
        copy.isCompleted = completed
        return copy
    }
}

// MARK: - Codable (tolerant to options added or removed later)

nonisolated extension OnboardingProfile: Codable {
    nonisolated private enum CodingKeys: String, CodingKey {
        case version, name, goals, difficulties, note, isCompleted
    }

    static let schemaVersion = 1

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        let goalRaw = try c.decodeIfPresent([String].self, forKey: .goals) ?? []
        goals = Set(goalRaw.compactMap(SleepGoal.init(rawValue:)))
        let difficultyRaw = try c.decodeIfPresent([String].self, forKey: .difficulties) ?? []
        difficulties = Set(difficultyRaw.compactMap(SleepDifficulty.init(rawValue:)))
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        isCompleted = try c.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schemaVersion, forKey: .version)
        try c.encode(name, forKey: .name)
        try c.encode(orderedGoals.map(\.rawValue), forKey: .goals)
        try c.encode(orderedDifficulties.map(\.rawValue), forKey: .difficulties)
        try c.encode(note, forKey: .note)
        try c.encode(isCompleted, forKey: .isCompleted)
    }
}

// MARK: - Sleep settings

/// Values the formulas read. Changing any of them recomputes every result.
nonisolated struct SleepSettings: Codable, Equatable, Sendable {
    /// Editable sleep need; start value 7 h 30 min.
    static let defaultGoalMinutes = 450

    var goalMinutes: Int = SleepSettings.defaultGoalMinutes
    /// Latest wake-up time, minutes after midnight (nil = use the usual wake time).
    var wakeMinutes: Int?
    /// Alarm on the latest wake-up time via AlarmKit.
    var alarmEnabled = false
    /// Haptics in the interface.
    var hapticsEnabled = true

    init(goalMinutes: Int = SleepSettings.defaultGoalMinutes, wakeMinutes: Int? = nil,
         alarmEnabled: Bool = false, hapticsEnabled: Bool = true) {
        self.goalMinutes = goalMinutes
        self.wakeMinutes = wakeMinutes
        self.alarmEnabled = alarmEnabled
        self.hapticsEnabled = hapticsEnabled
    }

    static let `default` = SleepSettings()
}
