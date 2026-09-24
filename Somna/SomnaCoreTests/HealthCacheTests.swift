import Foundation
import Testing
@testable import SomnaCore

@Suite("Кэш данных Health")
struct HealthCacheTests {
    @Test("Удаление и изменение записей в Health применяются по их ID")
    func addEditDelete() {
        var cache = HealthCache()
        let a = sample("2026-09-22 23:00", "2026-09-23 07:00", .core)
        let b = sample("2026-09-23 23:00", "2026-09-24 07:00", .core)
        cache.applySleep(added: [a, b], deleted: [])
        #expect(cache.sleep.count == 2)

        var edited = a
        edited.end = at("2026-09-23 06:00")
        cache.applySleep(added: [edited], deleted: [b.id])
        #expect(cache.sleep.count == 1)
        #expect(cache.sleep[a.id]?.end == at("2026-09-23 06:00"))

        var input = SomnaInput()
        cache.fill(&input)
        #expect(input.sleepSamples.count == 1)
    }

    @Test("Старые записи вне окна истории удаляются")
    func prune() {
        var cache = HealthCache()
        cache.applySleep(added: [sample("2026-05-01 23:00", "2026-05-02 07:00", .core),
                                 sample("2026-09-22 23:00", "2026-09-23 07:00", .core)], deleted: [])
        cache.prune(before: at("2026-06-01 00:00"))
        #expect(cache.sleep.count == 1)
    }

    @Test("Кэш кодируется и восстанавливается без потерь")
    func roundTrip() throws {
        var cache = HealthCache()
        cache.applySleep(added: [sample("2026-09-22 23:00", "2026-09-23 07:00", .deep)], deleted: [])
        cache.heartRate["2026-09-23"] = NightHeartRate(average: 55, minimum: 48)
        cache.anchors["sleep"] = Data([1, 2, 3])
        let data = try JSONEncoder().encode(cache)
        let back = try JSONDecoder().decode(HealthCache.self, from: data)
        #expect(back.sleep.count == 1)
        #expect(back.heartRateByNight()[day("2026-09-23")]?.minimum == 48)
        #expect(back.anchors["sleep"] == Data([1, 2, 3]))
    }

    @Test("Сброс: пустой кэш даёт пустой снимок")
    func cleared() {
        var cache = HealthCache()
        cache.applySleep(added: [sample("2026-09-22 23:00", "2026-09-23 07:00", .core)], deleted: [])
        cache = HealthCache()
        var i = input(samples: [])
        cache.fill(&i)
        #expect(SomnaEngine.compute(i).dataState == .noData)
    }
}

@Suite("Демо-данные (только для отладки)")
struct DemoDataTests {
    @Test("Демо-ночи проходят весь расчётный путь")
    func demoPipeline() throws {
        let cache = DemoHealthData.make(nights: 45, lastWakeDay: day("2026-09-30"), timeZone: moscow)
        var i = input(samples: [])
        cache.fill(&i)
        let s = SomnaEngine.compute(i)
        #expect(s.dataState == .ready(nights: 45))
        let latest = try #require(s.latest)
        #expect(latest.score != nil)
        #expect(latest.recovery?.status != .insufficient)
        #expect(latest.night.stages.hasDetailedStages)
        #expect(s.forecast.canPredict)
        #expect(s.sources.first?.id == DemoHealthData.watchID)
        let asleep = s.reports.map(\.night.asleepMinutes)
        #expect(asleep.allSatisfy { $0 > 300 && $0 < 540 })
        // The planted pattern (late caffeine → later, shorter sleep) is found.
        let caffeine = s.factorInsights.filter { $0.factorID == FactorCatalog.caffeineLate && $0.windowDays == 90 }
        #expect(caffeine.contains { $0.hasEnoughData })
    }
}
