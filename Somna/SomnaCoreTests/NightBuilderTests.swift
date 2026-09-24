import Foundation
import Testing
@testable import SomnaCore

@Suite("Сборка ночей")
struct NightBuilderTests {
    @Test("Стадии, бодрствование и «в кровати» считаются раздельно")
    func basicNight() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:30", .inBed, source: "watch"),
            sample("2026-09-22 23:20", "2026-09-23 02:00", .core),
            sample("2026-09-23 02:00", "2026-09-23 03:00", .deep),
            sample("2026-09-23 03:00", "2026-09-23 03:10", .awake),
            sample("2026-09-23 03:10", "2026-09-23 07:00", .rem)
        ]
        let h = NightBuilder.build(samples: samples, defaultTimeZone: moscow)
        let n = try #require(h.nights.first)
        #expect(h.nights.count == 1)
        #expect(n.dayKey == day("2026-09-23"))
        #expect(n.asleepMinutes == 160 + 60 + 230)
        #expect(n.awake == 10 * 60)
        #expect(n.awakenings == 1)
        #expect(n.stages.core == 160 * 60)
        #expect(n.stages.deep == 60 * 60)
        #expect(n.stages.rem == 230 * 60)
        #expect(num(n.latencyMinutes) == 20)
        #expect(num(n.timeInBed) == 510 * 60)
        let eff = try #require(n.efficiency)
        #expect(abs(eff - 450.0 / 510.0) < 1e-9)
    }

    @Test("Время в кровати другого устройства не смешивается с выбранной ночью")
    func foreignInBedIsIgnored() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:30", .inBed, source: "phone"),
            sample("2026-09-22 23:20", "2026-09-23 07:00", .core, source: "watch")
        ]
        let night = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(night.timeInBed == nil)
        #expect(night.latencyMinutes == nil)
        #expect(!night.continuityIsReliable)
    }

    @Test("Чужой приоритетный inBed не стирает inBed источника стадий")
    func overlappingInBedSourcesStaySeparate() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:00", .inBed, source: "phone"),
            sample("2026-09-22 23:15", "2026-09-23 06:45", .inBed, source: "watch"),
            sample("2026-09-22 23:20", "2026-09-23 06:45", .core, source: "watch")
        ]
        let preferences = [SourcePreference(sourceID: "phone", name: "iPhone", priority: 0),
                           SourcePreference(sourceID: "watch", name: "Watch", priority: 1)]
        let night = try #require(NightBuilder.build(samples: samples, preferences: preferences,
                                                    defaultTimeZone: moscow).nights.first)
        #expect(night.primarySourceID == "watch")
        #expect(num(night.timeInBed) == 450 * 60)
        #expect(num(night.latencyMinutes) == 5)
    }

    @Test("Неизвестный конец времени в кровати не превращается в надёжную непрерывность")
    func trailingUnknownTime() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:30", .inBed),
            sample("2026-09-22 23:10", "2026-09-23 07:00", .core)
        ]
        let night = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(night.unknownMinutes == 30)
        #expect(!night.continuityIsReliable)
    }

    @Test("Частичное время в кровати не расширяется до всей ночи")
    func partialInBedStaysPartial() throws {
        let samples = [
            sample("2026-09-23 01:00", "2026-09-23 03:00", .inBed),
            sample("2026-09-22 23:00", "2026-09-23 07:00", .core)
        ]
        let night = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(num(night.timeInBed) == 120 * 60)
        #expect(night.latencyMinutes == nil)
        #expect(night.measurements.timeInBed.status == .contradictory)
        #expect(!night.continuityIsReliable)
    }

    @Test("«В кровати» перекрывает стадии и не прибавляется ко сну")
    func inBedNotAdded() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:00", .inBed),
            sample("2026-09-22 23:15", "2026-09-23 06:45", .core)
        ]
        let n = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(n.asleepMinutes == 450)
        #expect(num(n.timeInBed) == 480 * 60)
    }

    @Test("Пауза до 90 минут объединяет сон в одну ночь")
    func gapUpTo90Merges() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 02:00", .core),
            sample("2026-09-23 03:20", "2026-09-23 07:00", .core)
        ]
        let h = NightBuilder.build(samples: samples, defaultTimeZone: moscow)
        #expect(h.nights.count == 1)
        #expect(h.naps.isEmpty)
        #expect(num(h.nights.first?.asleepMinutes) == 180 + 220)
    }

    @Test("Пауза больше 90 минут: основной сон — самый длинный, остальное — дневной сон")
    func gapOver90Splits() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 02:00", .core),
            sample("2026-09-23 03:40", "2026-09-23 07:00", .core)
        ]
        let h = NightBuilder.build(samples: samples, defaultTimeZone: moscow)
        #expect(h.nights.count == 1)
        #expect(num(h.nights.first?.asleepMinutes) == 200)
        #expect(h.naps.count == 1)
        #expect(num(h.naps.first?.asleep) == 180 * 60)
    }

    @Test("Дубликаты разных источников не суммируются: побеждает приоритетный источник")
    func duplicatesUseHighestPrioritySource() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:00", .core, source: "watch", name: "Apple Watch"),
            sample("2026-09-22 22:30", "2026-09-23 07:30", .asleepUnspecified, source: "phone", name: "iPhone")
        ]
        let auto = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(auto.asleepMinutes == 480)
        #expect(auto.sourceIDs == ["watch"])

        let prefs = [SourcePreference(sourceID: "phone", name: "iPhone", priority: 0),
                     SourcePreference(sourceID: "watch", name: "Apple Watch", priority: 1)]
        let chosen = try #require(NightBuilder.build(samples: samples, preferences: prefs, defaultTimeZone: moscow).nights.first)
        #expect(chosen.asleepMinutes == 540)
        #expect(chosen.stages.hasDetailedStages == false)
    }

    @Test("Одинаковые записи одного источника не удваиваются")
    func sameSourceOverlap() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:00", .asleepUnspecified),
            sample("2026-09-23 01:00", "2026-09-23 02:00", .deep),
            sample("2026-09-22 23:00", "2026-09-23 07:00", .asleepUnspecified)
        ]
        let n = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(n.asleepMinutes == 480)
        #expect(n.stages.deep == 3600)
        #expect(n.stages.unspecified == 420 * 60)
    }

    @Test("Пропуски в стадиях не считаются ни сном, ни бодрствованием")
    func gapsNotInvented() throws {
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 01:00", .core),
            sample("2026-09-23 01:30", "2026-09-23 06:00", .rem)
        ]
        let n = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(n.asleepMinutes == 120 + 270)
        #expect(n.awake == 0)
        #expect(n.awakenings == 0)
        #expect(n.latencyMinutes.isNone)
        #expect(n.efficiency == nil)
    }

    @Test("Ночь относится к дню пробуждения, даже если легли после полуночи")
    func wakeDayAfterMidnight() throws {
        let samples = [sample("2026-09-23 01:10", "2026-09-23 09:00", .core)]
        let n = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(n.dayKey == day("2026-09-23"))
        #expect(n.bedtimeScale == 13 * 60 + 10)
        #expect(n.wakeScale == 9 * 60)
    }

    @Test("Смена часового пояса: день и время — по местным часам")
    func timeZoneChange() throws {
        let kl = TimeZone(identifier: "Asia/Kuala_Lumpur")!
        let samples = [
            sample("2026-09-22 23:00", "2026-09-23 07:00", .core, tz: moscow),
            sample("2026-09-24 23:30", "2026-09-25 07:15", .core, tz: kl)
        ]
        let h = NightBuilder.build(samples: samples, defaultTimeZone: moscow)
        #expect(h.nights.count == 2)
        let second = h.nights[1]
        #expect(second.dayKey == day("2026-09-25"))
        #expect(second.timeZoneID == "Asia/Kuala_Lumpur")
        #expect(second.timeZoneChanged)
        #expect(second.wakeScale == 7 * 60 + 15)
        #expect(second.bedtimeScale == 11 * 60 + 30)
    }

    @Test("Переход на зимнее время: длительность по абсолютному времени, подъём — по местным часам")
    func daylightSaving() throws {
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        // 25 Oct 2026: clocks go back 03:00 → 02:00.
        let samples = [sample("2026-10-24 23:00", "2026-10-25 07:00", .core, tz: berlin)]
        let n = try #require(NightBuilder.build(samples: samples, defaultTimeZone: berlin).nights.first)
        #expect(n.asleepMinutes == 540)
        #expect(n.wakeScale == 420)
        #expect(n.dayKey == day("2026-10-25"))
    }

    @Test("Дневной сон не заменяет ночной")
    func napSeparate() throws {
        let samples = [
            sample("2026-09-22 23:30", "2026-09-23 07:00", .core),
            sample("2026-09-23 14:00", "2026-09-23 14:40", .core)
        ]
        let h = NightBuilder.build(samples: samples, defaultTimeZone: moscow)
        #expect(h.nights.count == 1)
        #expect(num(h.nights.first?.asleepMinutes) == 450)
        #expect(h.naps.count == 1)
        #expect(h.naps.first?.dayKey == day("2026-09-23"))
    }

    @Test("Короткая ночь сохраняется, но не валидна")
    func shortNightInvalid() throws {
        let samples = [sample("2026-09-23 03:00", "2026-09-23 05:00", .core)]
        let n = try #require(NightBuilder.build(samples: samples, defaultTimeZone: moscow).nights.first)
        #expect(!n.isValid)
    }

    @Test("Множество интервалов: объединение без двойного счёта")
    func intervalSet() {
        var set = IntervalSet()
        set.insert(0, 10)
        set.insert(20, 30)
        #expect(set.uncovered(5, 25).map { $0.0 } == [10])
        set.insert(8, 22)
        #expect(set.ranges.count == 1)
        #expect(set.total == 30)
    }
}
