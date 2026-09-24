//
//  Plan.swift
//  SomnaCore
//
//  Evening plan (v1): at most three actions, ranked as
//  1) the person's confirmed patterns (stable factor links in their data),
//  2) the sleep goal (bedtime from the wake time),
//  3) regularity (a steadier wake time),
//  then answers from the questionnaire as low-priority fillers.
//  Every action says why and where the data came from. No diagnoses.
//

import Foundation

nonisolated enum PlanActionKind: String, Codable, Sendable {
    case avoidFactor
    case seekFactor
    case screenOff
    case bedtime
    case wakeTime
    case habit
}

nonisolated struct PlanAction: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var kind: PlanActionKind
    var title: String
    /// Local time tonight (minutes after midnight; may exceed 1440 after midnight).
    var minutes: Int?
    var reason: String
    var source: String
    var systemImage: String
}

nonisolated struct RecoveryPlan: Codable, Hashable, Sendable {
    static let maximumActions = 3

    /// Evening the plan is for.
    var dayKey: DayKey
    var actions: [PlanAction]
    /// Suggested time in bed tonight (minutes after midnight, may exceed 1440).
    var bedtimeMinutes: Int
    /// Wake-up time used for the plan (minutes after midnight).
    var wakeMinutes: Int

    static func empty(day: DayKey, wake: Int, goal: Int) -> RecoveryPlan {
        RecoveryPlan(dayKey: day, actions: [], bedtimeMinutes: wake + 1440 - goal, wakeMinutes: wake)
    }
}

nonisolated enum PlanBuilder {
    /// Minimal link size worth acting on.
    static let minimumScoreEffect = 3.0
    static let minimumSleepEffect = 15.0
    /// Wake time counts as irregular above this mean deviation.
    static let irregularWakeMAD = 30.0
    static let screenOffLead = 45

    static func build(day: DayKey,
                      settings: SleepSettings,
                      wakeMinutes: Int,
                      profile: OnboardingProfile,
                      regularity: RegularityReport?,
                      forecast: ForecastModel,
                      insights: [FactorInsight],
                      factors: [JournalFactor],
                      nights: Int) -> RecoveryPlan {
        let goal = settings.goalMinutes
        let planningLoss = forecast.canPredict ? Int((forecast.planningLoss ?? 30).rounded()) : 30
        let wakeTonight = wakeMinutes + 1440
        let bedtime = roundTo5(wakeTonight - goal - planningLoss)

        var candidates: [(rank: Double, action: PlanAction)] = []

        // 1. Confirmed personal patterns.
        let byFactor = Dictionary(grouping: insights.filter { $0.isStable }, by: \.factorID)
        for factor in factors {
            guard let best = byFactor[factor.id]?.max(by: { effectSize($0) < effectSize($1) }) else { continue }
            let size = effectSize(best)
            guard size >= 1 else { continue }
            let sample = "\(best.withCount) и \(best.withoutCount) \(CoreFormat.plural(best.withoutCount, "ночь", "ночи", "ночей"))"
            let diff = best.outcome.formatDifference(best.difference ?? 0)
            let source = "Ваш журнал и Apple Health, \(best.windowDays) дней"
            if best.isUnfavourable && factor.avoidable {
                candidates.append((1000 + size, PlanAction(
                    id: "avoid-\(factor.id)",
                    kind: .avoidFactor,
                    title: avoidTitle(factor),
                    minutes: nil,
                    reason: "После дней с «\(factor.title.lowercased())» \(best.outcome.title.lowercased()) \(diff) (\(sample)). Это связь в ваших данных, не доказанная причина.",
                    source: source,
                    systemImage: factor.systemImage)))
            } else if !best.isUnfavourable && factor.id == FactorCatalog.daylight {
                candidates.append((900 + size, PlanAction(
                    id: "seek-\(factor.id)",
                    kind: .seekFactor,
                    title: "30 минут дневного света до 16:00",
                    minutes: nil,
                    reason: "После дней с дневным светом \(best.outcome.title.lowercased()) \(diff) (\(sample)).",
                    source: source,
                    systemImage: factor.systemImage)))
            }
        }

        // 2. Sleep goal.
        let bedText = CoreFormat.clock(Double(bedtime))
        let wakeText = CoreFormat.clock(Double(wakeMinutes))
        var bedReason = "Цель — \(CoreFormat.duration(minutes: Double(goal))) сна при подъёме в \(wakeText)."
        if forecast.canPredict {
            bedReason += " Заложен запас \(CoreFormat.duration(minutes: Double(planningLoss))) по вашим прошлым ночам."
        } else {
            bedReason += " Пока заложен условный запас 30 минут: точного прогноза ещё нет."
        }
        candidates.append((500, PlanAction(
            id: "bedtime",
            kind: .bedtime,
            title: "Лечь в кровать в \(bedText)",
            minutes: bedtime,
            reason: bedReason,
            source: nights > 0 ? "Цель сна и Apple Health, \(CoreFormat.nights(min(nights, ForecastModel.window)))" : "Цель сна",
            systemImage: "bed.double")))

        // 3. Regularity.
        if let r = regularity, r.wakeMAD > irregularWakeMAD {
            let usual = Int(r.medianWake.rounded())
            candidates.append((400 + r.wakeMAD, PlanAction(
                id: "wake",
                kind: .wakeTime,
                title: "Встать в \(CoreFormat.clock(Double(roundTo5(usual))))",
                minutes: roundTo5(usual) + 1440,
                reason: "Подъём за последние \(CoreFormat.nights(r.nights)) плавает в среднем на ±\(Int(r.wakeMAD.rounded())) мин. Одно время подъёма — самый сильный рычаг режима.",
                source: "Apple Health, \(CoreFormat.nights(r.nights))",
                systemImage: "sunrise")))
        }

        // 4. Questionnaire fillers.
        let screenTime = bedtime - screenOffLead
        if profile.difficulties.contains(.phoneInBed) || profile.goals.contains(.calmEvening) {
            candidates.append((200, PlanAction(
                id: "screen",
                kind: .screenOff,
                title: "Без экрана с \(CoreFormat.clock(Double(screenTime)))",
                minutes: screenTime,
                reason: "Вы отметили в анкете, что телефон в кровати или вечер без спокойствия мешает спать.",
                source: "Анкета",
                systemImage: "iphone.slash")))
        }
        if profile.difficulties.contains(.lateCaffeine) {
            candidates.append((150, PlanAction(
                id: "caffeine",
                kind: .habit,
                title: "Последний кофе до 14:00",
                minutes: 14 * 60,
                reason: "Вы отметили в анкете, что пьёте кофеин вечером.",
                source: "Анкета",
                systemImage: "cup.and.saucer")))
        }

        var taken = Set<String>()
        var ranked: [PlanAction] = []
        for c in candidates.sorted(by: { $0.rank > $1.rank }) {
            // A questionnaire filler is dropped when the same habit is already a confirmed pattern.
            if c.action.id == "caffeine", taken.contains("avoid-\(FactorCatalog.caffeineLate)") { continue }
            if c.action.id == "screen", taken.contains("avoid-\(FactorCatalog.screenInBed)") { continue }
            guard !taken.contains(c.action.id) else { continue }
            taken.insert(c.action.id)
            ranked.append(c.action)
        }
        let actions = Array(ranked.prefix(RecoveryPlan.maximumActions))
            .sorted { ($0.minutes ?? -1) < ($1.minutes ?? -1) }
        return RecoveryPlan(dayKey: day, actions: actions, bedtimeMinutes: bedtime, wakeMinutes: wakeMinutes)
    }

    /// Link size on a common scale: score points, or sleep minutes ÷ 5.
    static func effectSize(_ insight: FactorInsight) -> Double {
        guard let d = insight.difference else { return 0 }
        switch insight.outcome {
        case .score: return abs(d) >= minimumScoreEffect ? abs(d) : 0
        case .asleep, .latency: return abs(d) >= minimumSleepEffect ? abs(d) / 5 : 0
        case .energy: return abs(d) >= 0.5 ? abs(d) * 6 : 0
        }
    }

    static func avoidTitle(_ factor: JournalFactor) -> String {
        switch factor.id {
        case FactorCatalog.caffeineLate: "Без кофеина после 14:00"
        case FactorCatalog.alcohol: "Сегодня без алкоголя"
        case FactorCatalog.lateMeal: "Ужин за 3 часа до сна"
        case FactorCatalog.screenInBed: "Телефон — вне кровати"
        case FactorCatalog.lateWorkout: "Тренировку — до 19:00"
        case FactorCatalog.nap: "Без дневного сна после 15:00"
        case FactorCatalog.roomHot: "Проветрить спальню перед сном"
        case FactorCatalog.roomNoise: "Беруши или белый шум"
        case FactorCatalog.roomLight: "Затемнить спальню"
        default: "Сегодня без «\(factor.title.lowercased())»"
        }
    }

    static func roundTo5(_ minutes: Int) -> Int {
        Int((Double(minutes) / 5).rounded()) * 5
    }
}
