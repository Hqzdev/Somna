import Foundation
import Testing
@testable import SomnaCore

@Suite("Снимок данных")
struct EngineTests {
    private func history(_ count: Int, bed: Int = 24 * 60, wake: Int = 7 * 60) -> [SleepSample] {
        nights(count: count, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: bed, wake: wake, inBed: true, latency: 10)
        }
    }

    @Test("Нет данных — пустой снимок без выдуманных чисел")
    func empty() {
        let s = SomnaEngine.compute(input(samples: []))
        #expect(s.dataState == .noData)
        #expect(s.latest == nil)
        #expect(s.balance == nil)
        #expect(s.regularity == nil)
        #expect(!s.forecast.canPredict)
        #expect(s.plan.actions.count <= RecoveryPlan.maximumActions)
    }

    @Test("Меньше 7 ночей — сбор данных, баланс предварительный")
    func collecting() throws {
        let s = SomnaEngine.compute(input(samples: history(4)))
        #expect(s.dataState == .collecting(nights: 4))
        #expect(s.balance?.isPreliminary == true)
        // A score from the first nights, without the rhythm until 7 comparable nights.
        #expect(s.regularity == nil)
        #expect(s.regularityNightsMissing == 3)
        let score = try #require(s.latest?.score)
        #expect(score.isPartial)
        #expect(s.latest?.rhythmNightsMissing == 4)
        #expect(s.latest?.explanation?.contains("через 4 ночи") == true)
        // Partial scores stay out of factor comparisons.
        #expect(s.outcomes.values[.score]?.isEmpty ?? true)
    }

    @Test("Изменение цели пересчитывает оценку, баланс и план")
    func goalRecomputes() throws {
        var i = input(samples: history(14))
        i.settings.goalMinutes = 420
        let a = SomnaEngine.compute(i)
        i.settings.goalMinutes = 480
        let b = SomnaEngine.compute(i)
        let sa = try #require(a.latest?.score?.value)
        let sb = try #require(b.latest?.score?.value)
        #expect(sa > sb)
        #expect(try #require(a.balance).deficitMinutes == 0)
        #expect(try #require(b.balance).deficitMinutes == 14 * 60)
        #expect(a.plan.bedtimeMinutes != b.plan.bedtimeMinutes)
    }

    @Test("Утренняя оценка влияет на предложение потребности во сне")
    func checkInRecomputes() {
        var i = input(samples: history(24, bed: 23 * 60, wake: 7 * 60))
        #expect(SomnaEngine.compute(i).needSuggestion == nil)
        i.checkIns = (0..<21).map { MorningCheckIn(dayKey: day("2026-09-30").adding(days: -$0), energy: 5, quality: 5) }
        let s = SomnaEngine.compute(i)
        #expect(s.needSuggestion?.suggestedMinutes == 480)
    }

    @Test("Приоритет источника меняет итог ночи")
    func sourcePriorityRecomputes() throws {
        let samples = [
            sample("2026-09-29 23:00", "2026-09-30 07:00", .core, source: "watch", name: "Apple Watch"),
            sample("2026-09-29 22:00", "2026-09-30 08:00", .asleepUnspecified, source: "app", name: "AutoSleep")
        ]
        var i = input(samples: samples)
        #expect(try #require(SomnaEngine.compute(i).latest).night.asleepMinutes == 480)
        i.sourcePreferences = [SourcePreference(sourceID: "app", name: "AutoSleep", priority: 0)]
        #expect(try #require(SomnaEngine.compute(i).latest).night.asleepMinutes == 600)
    }

    @Test("Удалённая в Health запись исчезает из расчёта")
    func deletionRecomputes() {
        let samples = history(8)
        let before = SomnaEngine.compute(input(samples: samples))
        let after = SomnaEngine.compute(input(samples: Array(samples.dropLast(2))))
        #expect(before.reports.count == 8)
        #expect(after.reports.count == 7)
    }

    @Test("Готовые данные: объяснение, прогноз и план с причинами")
    func ready() throws {
        let s = SomnaEngine.compute(input(samples: history(40)))
        #expect(s.dataState == .ready(nights: 40))
        let latest = try #require(s.latest)
        #expect(latest.score != nil)
        #expect(latest.explanation?.isEmpty == false)
        #expect(s.forecast.canPredict)
        #expect(!s.plan.actions.isEmpty)
        #expect(s.plan.actions.count <= 3)
        #expect(s.wakeMinutes == 7 * 60)
        #expect(s.sources.first?.id == "watch")
    }

    @Test("Будущие ночи не попадают в снимок")
    func futureIgnored() {
        let s = SomnaEngine.compute(input(samples: history(5), now: "2026-09-28 12:00"))
        #expect(s.reports.allSatisfy { $0.dayKey <= day("2026-09-28") })
    }
}
