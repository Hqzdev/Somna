import Foundation
import Testing
@testable import SomnaCore

@Suite("Факторы, эксперименты, тренды, план")
struct InsightTests {
    private func outcomes(_ values: [DayKey: Double], _ metric: OutcomeMetric = .score) -> OutcomeTable {
        OutcomeTable(values: [metric: values],
                     sleepOpportunity: values.mapValues { _ in 480 },
                     previousSleep: values.mapValues { _ in 450 })
    }

    @Test("Фактор: разница медиан, выборка и интервал; устойчивая связь — не причина")
    func factorStable() throws {
        let end = day("2026-09-30")
        var values: [DayKey: Double] = [:]
        var scores: [DayKey: Double] = [:]
        for i in 0..<24 {
            let factorDay = end.adding(days: -(i + 1))
            let with = i % 2 == 0
            values[factorDay] = with ? 1 : 0
            scores[factorDay.adding(days: 1)] = with ? 70 + Double(i % 3) : 80 + Double(i % 3)
        }
        let factor = FactorCatalog.builtIn.first { $0.id == FactorCatalog.caffeineLate }!
        var insights = [FactorAnalyzer.analyze(factor: factor, values: values, outcomes: outcomes(scores),
                                               outcome: .score, endDay: end, windowDays: 30)]
        FactorAnalyzer.adjustFalseDiscovery(&insights)
        let insight = insights[0]
        #expect(insight.withCount == 12)
        #expect(insight.withoutCount == 12)
        #expect(abs(num(insight.difference) + 10) <= 2)
        #expect(insight.pairCount >= 8)
        #expect(insight.isStable)
        #expect(insight.isUnfavourable)
    }

    @Test("Меньше 6 ночей в группе — «недостаточно данных»")
    func factorInsufficient() {
        let end = day("2026-09-30")
        var values: [DayKey: Double] = [:]
        var scores: [DayKey: Double] = [:]
        for i in 0..<10 {
            let d = end.adding(days: -(i + 1))
            values[d] = i < 5 ? 1 : 0
            scores[d.adding(days: 1)] = 75
        }
        let factor = FactorCatalog.builtIn[0]
        let insight = FactorAnalyzer.analyze(factor: factor, values: values, outcomes: outcomes(scores),
                                             outcome: .score, endDay: end, windowDays: 30)
        #expect(!insight.hasEnoughData)
        #expect(insight.difference.isNone)
        #expect(!insight.isStable)
    }

    @Test("Окно 7 дней берёт только последние ночи")
    func factorWindow() {
        let end = day("2026-09-30")
        var values: [DayKey: Double] = [:]
        var scores: [DayKey: Double] = [:]
        for i in 0..<30 {
            let d = end.adding(days: -(i + 1))
            values[d] = Double(i % 2)
            scores[d.adding(days: 1)] = 80
        }
        let insight = FactorAnalyzer.analyze(factor: FactorCatalog.builtIn[0], values: values, outcomes: outcomes(scores),
                                             outcome: .score, endDay: end, windowDays: 7)
        #expect(insight.withCount + insight.withoutCount == 7)
    }

    @Test("Журнал важнее Health; без данных фактор неизвестен")
    func resolver() {
        let tz = moscow
        let q = [
            QuantitySample(id: "c1", kind: .caffeine, start: at("2026-09-20 16:00"), end: at("2026-09-20 16:00"), value: 80),
            QuantitySample(id: "c2", kind: .caffeine, start: at("2026-09-21 09:00"), end: at("2026-09-21 09:00"), value: 80)
        ]
        let journal = [JournalEntry(dayKey: day("2026-09-21"), factorID: FactorCatalog.caffeineLate, value: 1)]
        let r = FactorResolver.resolve(factors: FactorCatalog.builtIn, journal: journal, quantities: q, workouts: [],
                                       naps: [], nightDays: [], timeZone: tz)
        let caffeine = r[FactorCatalog.caffeineLate] ?? [:]
        #expect(caffeine[day("2026-09-20")] == 1)
        #expect(caffeine[day("2026-09-21")] == 1) // journal overrides Health's morning-only record
        #expect(caffeine[day("2026-09-22")] == nil) // unknown, not «no»
        #expect(r[FactorCatalog.workout] == nil)
    }

    @Test("Тренировки: при наличии записей дни без тренировки — «нет»")
    func workoutsFillZeros() {
        let w = [WorkoutSample(id: "w", start: at("2026-09-20 20:00"), end: at("2026-09-20 21:00"), activityName: "Бег")]
        let r = FactorResolver.resolve(factors: FactorCatalog.builtIn, journal: [], quantities: [], workouts: w,
                                       naps: [], nightDays: [], timeZone: moscow)
        #expect(r[FactorCatalog.workout]?[day("2026-09-20")] == 1)
        #expect(r[FactorCatalog.lateWorkout]?[day("2026-09-20")] == 1)
        #expect(r[FactorCatalog.workout]?[day("2026-09-21")] == 0)
    }

    @Test("Эксперимент: 14 сопоставимых пар и отмеченная привычка")
    func experiment() {
        let start = day("2026-09-10")
        var asleep: [DayKey: Double] = [:]
        for i in 0..<14 { asleep[start.adding(days: -i)] = 400 }
        for i in 1...14 { asleep[start.adding(days: i)] = 430 }
        let e = Experiment(id: "x", title: "Свет утром", detail: "", metric: .asleep, startDay: start,
                           doneDays: (0..<14).map { start.adding(days: $0) })
        let r = ExperimentAnalyzer.analyze(e, outcomes: outcomes(asleep, .asleep), today: day("2026-09-30"))
        #expect(r.baselineCount == 14)
        #expect(r.experimentCount == 14)
        #expect(num(r.difference) == 30)
        #expect(r.isInterpretable)
        #expect(r.isImprovement)
        #expect(r.isComplete)

        var sparse = asleep
        for i in 0..<5 { sparse[start.adding(days: -i)] = nil }
        let r2 = ExperimentAnalyzer.analyze(e, outcomes: outcomes(sparse, .asleep), today: day("2026-09-30"))
        #expect(r2.baselineCount == 9)
        #expect(!r2.isInterpretable)
    }

    @Test("Тренд: медиана 7 ночей против 28 предыдущих; устойчивость")
    func trend() throws {
        let end = day("2026-09-30")
        var series: [DayKey: Double] = [:]
        for i in 7..<35 { series[end.adding(days: -i)] = 50 + Double(i % 5) - 2 }
        for i in 0..<7 { series[end.adding(days: -i)] = 38 }
        let t = try #require(TrendAnalyzer.analyze(metric: .hrv, series: series, endDay: end))
        #expect(t.recentMedian == 38)
        #expect(t.priorMedian == 50)
        #expect(t.isSustained)
        #expect(!t.isUp)

        var small = series
        for i in 0..<7 { small[end.adding(days: -i)] = 50.5 }
        #expect(TrendAnalyzer.analyze(metric: .hrv, series: small, endDay: end)?.isSustained == false)

        let short = series.filter { $0.key >= end.adding(days: -15) }
        #expect(TrendAnalyzer.analyze(metric: .hrv, series: short, endDay: end) == nil)
    }

    @Test("План: максимум 3 действия; время отхода учитывает консервативную потерю")
    func plan() throws {
        var profile = OnboardingProfile()
        profile.difficulties = [.phoneInBed, .lateCaffeine]
        let forecast = ForecastModel(nights: 30, goalMinutes: 450, medianLatency: 15, medianAwake: 10,
                                     medianLoss: 25, planningLoss: 25, historicalLowWindow: 400,
                                     historicalHighWindow: 600, errorLow: -10, errorHigh: 10)
        let stable = FactorInsight(factorID: FactorCatalog.alcohol, title: "Алкоголь", windowDays: 30, outcome: .score,
                                   withCount: 10, withoutCount: 12, medianWith: 68, medianWithout: 80,
                                   difference: -12, intervalLow: -16, intervalHigh: -6,
                                   pairCount: 8, pValue: 0.001, qValue: 0.01)
        let plan = PlanBuilder.build(day: day("2026-09-30"), settings: SleepSettings(goalMinutes: 450),
                                     wakeMinutes: 7 * 60, profile: profile, regularity: nil, forecast: forecast,
                                     insights: [stable], factors: FactorCatalog.builtIn, nights: 10)
        #expect(plan.actions.count == 3)
        #expect(plan.bedtimeMinutes == 7 * 60 + 1440 - 450 - 25) // 23:05
        #expect(plan.actions.contains { $0.id == "avoid-\(FactorCatalog.alcohol)" })
        #expect(plan.actions.contains { $0.id == "bedtime" })
        #expect(plan.actions.allSatisfy { !$0.reason.isEmpty && !$0.source.isEmpty })
    }

    @Test("План никогда не предлагает отказаться от лекарств")
    func planNeverMedication() {
        let med = FactorInsight(factorID: FactorCatalog.medication, title: "Лекарства", windowDays: 30, outcome: .score,
                                withCount: 10, withoutCount: 10, medianWith: 60, medianWithout: 80,
                                difference: -20, intervalLow: -25, intervalHigh: -15)
        let plan = PlanBuilder.build(day: day("2026-09-30"), settings: .default, wakeMinutes: 420,
                                     profile: .empty, regularity: nil, forecast: .empty,
                                     insights: [med], factors: FactorCatalog.builtIn, nights: 0)
        #expect(!plan.actions.contains { $0.id.contains(FactorCatalog.medication) })
    }
}
