import Foundation
import Testing
@testable import SomnaCore

@Suite("Оценка сна, регулярность, недобор и цель")
struct ScoreTests {
    @Test("Недобор снижает достаточность нелинейно, избыток не награждается")
    func durationAnchors() {
        #expect(SleepScore.durationComponent(asleepMinutes: 450, goalMinutes: 450) == 100)
        #expect(SleepScore.durationComponent(asleepMinutes: 420, goalMinutes: 450) == 85)
        #expect(SleepScore.durationComponent(asleepMinutes: 390, goalMinutes: 450) == 65)
        #expect(SleepScore.durationComponent(asleepMinutes: 330, goalMinutes: 450) == 25)
        #expect(SleepScore.durationComponent(asleepMinutes: 500, goalMinutes: 450) == 100)
    }

    @Test("При одинаковой длительности прерывистый сон оценивается ниже")
    func fragmentationChangesScore() throws {
        let evening = day("2026-09-22")
        let calm = try #require(NightBuilder.build(samples: simpleNight(evening: evening, bed: 23 * 60, wake: 7 * 60 + 30,
                                                                         inBed: true, latency: 10), defaultTimeZone: moscow).nights.first)
        let fragmented = try #require(NightBuilder.build(samples: simpleNight(evening: evening, bed: 23 * 60,
                                                                              wake: 8 * 60 + 10, inBed: true,
                                                                              latency: 10, awake: 40), defaultTimeZone: moscow).nights.first)
        #expect(calm.asleepMinutes == fragmented.asleepMinutes)
        let a = try #require(SleepScore.compute(components: SleepScore.components(night: calm, goalMinutes: 450, rhythm: 90)))
        let b = try #require(SleepScore.compute(components: SleepScore.components(night: fragmented, goalMinutes: 450, rhythm: 90)))
        #expect(a.value > b.value)
        #expect(a.components.continuity! > b.components.continuity!)
    }

    @Test("Нет непрерывности — нет ложного общего балла; без ритма — частичный балл")
    func noPseudoPrecision() throws {
        #expect(SleepScore.compute(components: ScoreComponents(duration: 100, regularity: 80)) == nil)
        let partial = try #require(SleepScore.compute(components: ScoreComponents(duration: 100, continuity: 90)))
        #expect(partial.value == 95)
        #expect(partial.isPartial)
        let score = SleepScore.compute(components: ScoreComponents(duration: 100, regularity: 100, continuity: 0))
        #expect(score?.value == 25)
        #expect(score?.isPartial == false)
    }

    @Test("Ритм берётся из предыдущих ночей, текущая не меняет собственную базу")
    func regularityPastOnly() throws {
        let history = NightBuilder.build(samples: nights(count: 8, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: 23 * 60, wake: 7 * 60)
        }, defaultTimeZone: moscow).nights
        let current = try #require(history.last)
        #expect(RegularityReport.rhythm(for: current, previous: Array(history.dropLast())) == 100)
        #expect(RegularityReport.rhythm(for: history[5], previous: Array(history.prefix(5))) == nil)
    }

    @Test("Недобор и избыток показываются отдельно за 14 календарных дней")
    func balanceDoesNotCancel() throws {
        let history = NightBuilder.build(samples: nights(count: 14, lastWakeDay: day("2026-09-30")) { i, e in
            simpleNight(evening: e, bed: i < 7 ? 24 * 60 : 23 * 60, wake: 7 * 60)
        }, defaultTimeZone: moscow).nights
        let result = try #require(SleepBalance.compute(nights: history, goalMinutes: 450))
        #expect(result.hasCoverage)
        #expect(result.shortfallMinutes == 210)
        #expect(result.extraMinutes == 210)
        #expect(result.deficitMinutes == 210)
    }

    @Test("Подтверждённая короткая ночь входит в недобор, но не в личную норму")
    func shortNightCountsAsObservedShortfall() throws {
        let short = try #require(NightBuilder.build(samples: [sample("2026-09-23 03:00", "2026-09-23 05:00", .core)],
                                                    defaultTimeZone: moscow).nights.first)
        #expect(!short.isValid)
        let balance = try #require(SleepBalance.compute(nights: [short], goalMinutes: 450))
        #expect(balance.availableDays == 1)
        #expect(balance.shortfallMinutes == 330)
        #expect(!balance.hasCoverage)
    }

    @Test("Изменённая цель действует только с указанного дня")
    func goalHistory() throws {
        let history = NightBuilder.build(samples: nights(count: 14, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: 23 * 60, wake: 7 * 60)
        }, defaultTimeZone: moscow).nights
        let changes = [GoalChange(effectiveDay: day("1900-01-01"), minutes: 450),
                       GoalChange(effectiveDay: day("2026-09-24"), minutes: 480)]
        let result = try #require(SleepBalance.compute(nights: history, goalMinutes: 480, goalHistory: changes))
        #expect(result.entries.first?.goalMinutes == 450)
        #expect(result.entries.last?.goalMinutes == 480)
    }

    @Test("Цель предлагается лишь после устойчивых парных оценок сна и энергии")
    func sleepNeed() {
        let history = NightBuilder.build(samples: nights(count: 24, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: 23 * 60, wake: 7 * 60)
        }, defaultTimeZone: moscow).nights
        let checked = Dictionary(uniqueKeysWithValues: history.map {
            ($0.dayKey, MorningCheckIn(dayKey: $0.dayKey, energy: 5, quality: 5))
        })
        #expect(SleepNeedSuggestion.compute(nights: history, checkIns: checked, currentGoal: 450)?.suggestedMinutes == 480)
        #expect(SleepNeedSuggestion.compute(nights: history, checkIns: [:], currentGoal: 450) == nil)
    }

    @Test("Калибровка не использует текущую оценку и включается лишь после улучшения на отложенных ночах")
    func personalizedCalibration() throws {
        let night = try #require(NightBuilder.build(samples: simpleNight(evening: day("2026-09-22"),
                                                                         bed: 23 * 60, wake: 7 * 60,
                                                                         inBed: true), defaultTimeZone: moscow).nights.first)
        let base = SleepScore(value: 50, components: ScoreComponents(), baseValue: 50)
        let paired = (0..<60).map { i in
            let quality = 2 + i % 3
            return RatedNight(baseScore: Double(quality * 20 - 10), perceivedQuality: quality,
                              deepFraction: -1, remFraction: -1)
        }
        #expect(ScorePersonalizer.apply(base, night: night, previous: Array(paired.prefix(59))).value == 50)
        let adjusted = ScorePersonalizer.apply(base, night: night, previous: paired)
        #expect(adjusted.isPersonalized)
        #expect(adjusted.value == 60)
        let alreadyExact = paired.map { RatedNight(baseScore: Double($0.perceivedQuality * 20),
                                                   perceivedQuality: $0.perceivedQuality,
                                                   deepFraction: -1, remFraction: -1) }
        #expect(!ScorePersonalizer.apply(base, night: night, previous: alreadyExact).isPersonalized)
    }

    @Test("Стадии могут дать не более пяти баллов лишь после отдельной проверки")
    func separatelyValidatedStages() throws {
        var night = try #require(NightBuilder.build(samples: simpleNight(evening: day("2026-09-22"),
                                                                         bed: 23 * 60, wake: 7 * 60,
                                                                         inBed: true), defaultTimeZone: moscow).nights.first)
        night.stages.core = night.asleep * 0.5
        night.stages.deep = night.asleep * 0.3
        night.stages.rem = night.asleep * 0.2
        night.stages.unspecified = 0
        let base = SleepScore(value: 50, components: ScoreComponents(), baseValue: 50)
        let pairs = (0..<90).map { i in
            RatedNight(baseScore: 50, perceivedQuality: i.isMultiple(of: 2) ? 2 : 3,
                       deepFraction: i.isMultiple(of: 2) ? 0.1 : 0.3, remFraction: 0.2)
        }
        #expect(!ScorePersonalizer.apply(base, night: night, previous: Array(pairs.prefix(89))).isPersonalized)
        let adjusted = ScorePersonalizer.apply(base, night: night, previous: pairs)
        #expect(adjusted.isPersonalized)
        #expect(adjusted.value > 50 && adjusted.value <= 55)
    }
}
