//
//  WidgetPublisher.swift
//  Somna
//
//  Projects the current snapshot into WidgetSnapshot (App Group) and reloads
//  the iPhone widgets when what they show changed. Widget links
//  (somna://night, somna://plan, somna://today) open the matching screen.
//

import Foundation
import WidgetKit

enum WidgetPublisher {
    static func publish(_ store: SomnaStore) {
        guard store.hasLoaded else { return }
        let snapshot = WidgetSnapshot.make(from: store.snapshot,
                                           statuses: store.planStatuses,
                                           alarmEnabled: store.settings.alarmEnabled,
                                           isOnboarded: store.isOnboarded,
                                           syncedAt: store.lastSync,
                                           now: Date())
        if WidgetSnapshotStore.save(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

extension AppState {
    /// Opens a link from an iPhone widget.
    func open(widgetLink url: URL) {
        guard url.scheme == "somna" else { return }
        sheet = nil
        cover = nil
        switch url.host() {
        case "night":
            selectedNight = nil
            go(to: .sleep)
        case "plan":
            planPath = [.eveningPlan]
            go(to: .plan, reset: false)
        default:
            go(to: .today)
        }
    }
}

// MARK: - Projection

nonisolated extension WidgetSnapshot {
    static func make(from s: SomnaSnapshot,
                     statuses: [String: PlanStepStatus],
                     alarmEnabled: Bool,
                     isOnboarded: Bool,
                     syncedAt: Date?,
                     now: Date) -> WidgetSnapshot {
        var result = WidgetSnapshot(generatedAt: now,
                                    timeZoneID: s.timeZone.identifier,
                                    isOnboarded: isOnboarded,
                                    night: nil,
                                    shortfall: nil,
                                    plan: nil)
        if let report = s.latest {
            result.night = night(report, in: s, syncedAt: syncedAt)
        }
        if let balance = s.balance {
            result.shortfall = Shortfall(minutes: Int(balance.shortfallMinutes.rounded()),
                                         isPreliminary: balance.isPreliminary)
        }
        result.plan = plan(s, statuses: statuses, alarmEnabled: alarmEnabled)
        return result
    }

    private static func night(_ report: NightReport, in s: SomnaSnapshot, syncedAt: Date?) -> Night {
        let sleep = report.night
        // Same baseline as the Today screen: median of the previous 30 scores, from 7 nights.
        let previous = s.reports.filter { $0.dayKey < report.dayKey }.suffix(30).compactMap { $0.score?.value }
        let norm = previous.count >= 7 ? Stats.median(previous.map(Double.init)).map { Int($0.rounded()) } : nil
        let stages = sleep.stages
        let names = sleep.sourceIDs.compactMap { id in s.sources.first { $0.id == id }?.name }
        return Night(sleepStart: sleep.sleepStart,
                     sleepEnd: sleep.sleepEnd,
                     asleepMinutes: Int(sleep.asleepMinutes.rounded()),
                     goalMinutes: report.goalMinutes,
                     score: report.score?.value,
                     scoreLabel: report.score?.label,
                     norm: norm,
                     recovery: report.recovery.flatMap { recoveryText($0.status) },
                     sourceName: names.first,
                     syncedAt: syncedAt,
                     stages: stages.hasDetailedStages
                        ? Stages(deep: minutes(stages.deep), core: minutes(stages.core),
                                 rem: minutes(stages.rem), awake: minutes(sleep.awake))
                        : nil,
                     segments: segments(sleep))
    }

    private static func plan(_ s: SomnaSnapshot, statuses: [String: PlanStepStatus], alarmEnabled: Bool) -> Plan {
        let plan = s.plan
        let tz = s.timeZone
        let bed = plan.dayKey.date(atMinutes: plan.bedtimeMinutes, in: tz)
        let wake = plan.dayKey.date(atMinutes: plan.wakeMinutes + 1440, in: tz)
        let forecast = s.forecast.forecast(bedtime: bed, wake: wake)
        let steps: [Step] = plan.actions.map { action in
            Step(id: action.id,
                 title: title(action),
                 short: short(action),
                 minutes: action.minutes,
                 systemImage: action.systemImage,
                 status: StepStatus(rawValue: (statuses[action.id] ?? .pending).rawValue) ?? .pending)
        }
        return Plan(day: plan.dayKey.description,
                    bedtimeMinutes: plan.bedtimeMinutes,
                    wakeMinutes: plan.wakeMinutes,
                    windDownMinutes: plan.actions.first { $0.kind == .screenOff }?.minutes,
                    predictedSleepMinutes: forecast.predictedMinutes.map { Int($0.rounded()) },
                    balanceChangeMinutes: forecast.balanceChangeMinutes.map { Int($0.rounded()) },
                    alarmEnabled: alarmEnabled,
                    steps: steps)
    }

    private static func segments(_ sleep: SleepNight) -> [Segment] {
        let start = sleep.sleepStart
        let total = sleep.sleepEnd.timeIntervalSince(start)
        guard total > 0 else { return [] }
        var result: [Segment] = []
        for interval in sleep.intervals.sorted(by: { $0.start < $1.start }) {
            let stage: Stage
            switch interval.stage {
            case .awake: stage = .awake
            case .rem: stage = .rem
            case .core: stage = .core
            case .deep: stage = .deep
            case .asleepUnspecified: stage = .asleep
            case .inBed: continue
            }
            let a = max(0, min(1, interval.start.timeIntervalSince(start) / total))
            let b = max(0, min(1, interval.end.timeIntervalSince(start) / total))
            guard b > a else { continue }
            if var last = result.last, last.stage == stage, a - last.end < 0.002 {
                last.end = max(last.end, b)
                result[result.count - 1] = last
            } else {
                result.append(Segment(start: a, end: b, stage: stage))
            }
        }
        return Array(result.prefix(160))
    }

    private static func minutes(_ seconds: TimeInterval) -> Int {
        Int((seconds / 60).rounded())
    }

    private static func recoveryText(_ status: RecoveryStatus) -> String? {
        switch status {
        case .ordinary: "как обычно"
        case .lowerThanUsual: "ниже обычного"
        case .mixed: "неоднозначно"
        case .insufficient: nil
        }
    }

    private static func title(_ action: PlanAction) -> String {
        switch action.kind {
        case .bedtime: "Лечь в кровать"
        case .screenOff: "Режим без экрана"
        case .wakeTime: "Подъём"
        default: action.title
        }
    }

    private static func short(_ action: PlanAction) -> String {
        switch action.kind {
        case .bedtime: "в кровать"
        case .screenOff: "без экрана"
        case .wakeTime: "подъём"
        default: String(action.title.prefix(1)).lowercased() + String(action.title.dropFirst())
        }
    }
}
