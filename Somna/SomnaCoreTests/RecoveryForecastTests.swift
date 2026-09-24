import Foundation
import Testing
@testable import SomnaCore

@Suite("Восстановление и прогноз")
struct RecoveryForecastTests {
    @Test("Личная база: медиана и 1,4826 × MAD, минимум 14 измерений")
    func baseline() throws {
        let values: [Double] = [48, 50, 52, 49, 51, 50, 47, 53, 50, 50, 49, 51, 48, 52]
        let b = try #require(MetricBaseline.compute(kind: .hrv, values: values))
        #expect(b.median == 50)
        #expect(abs(b.scale - 1.4826) < 1e-9) // MAD = 1
        #expect(MetricBaseline.compute(kind: .hrv, values: Array(values.prefix(13))) == nil)
    }

    @Test("Несколько отклонений дают текстовый сигнал без псевдоточного балла")
    func recoveryTotal() throws {
        let hrv = MetricBaseline(kind: .hrv, median: 50, scale: 5, count: 20)
        let rhr = MetricBaseline(kind: .restingHeartRate, median: 55, scale: 2, count: 20)
        var vitals = NightVitals()
        vitals.hrv = 40
        vitals.restingHeartRate = 57
        let r = RecoveryReport.compute(asleepMinutes: 450, goalMinutes: 450,
                                       vitals: vitals, hrvBaseline: hrv, rhrBaseline: rhr)
        #expect(r.hrvDeviation == -2)
        #expect(r.rhrDeviation == 1)
        #expect(r.status == .lowerThanUsual)
    }

    @Test("Без личной базы — никаких физиологических выводов")
    func recoveryWithoutBaseline() {
        var vitals = NightVitals()
        vitals.hrv = 40
        let r = RecoveryReport.compute(asleepMinutes: 420, goalMinutes: 450,
                                       vitals: vitals, hrvBaseline: nil, rhrBaseline: nil)
        #expect(r.status == .insufficient)
        #expect(!r.hasPhysiology)
    }

    @Test("Один физиологический показатель не превращается в точный балл")
    func recoveryPartial() {
        let rhr = MetricBaseline(kind: .restingHeartRate, median: 55, scale: 2, count: 20)
        var vitals = NightVitals()
        vitals.restingHeartRate = 55
        let r = RecoveryReport.compute(asleepMinutes: 420, goalMinutes: 450,
                                       vitals: vitals, hrvBaseline: nil, rhrBaseline: rhr)
        #expect(r.status == .ordinary)
    }

    @Test("Пульс в покое берётся за день пробуждения")
    func vitalsResting() throws {
        let night = try #require(NightBuilder.build(samples: [sample("2026-09-22 23:00", "2026-09-23 07:00", .core)],
                                                    defaultTimeZone: moscow).nights.first)
        let samples: [QuantityKind: [QuantitySample]] = [
            .restingHeartRate: [
                QuantitySample(id: "a", kind: .restingHeartRate, start: at("2026-09-22 10:00"), end: at("2026-09-22 10:00"), value: 60),
                QuantitySample(id: "b", kind: .restingHeartRate, start: at("2026-09-23 09:00"), end: at("2026-09-23 09:00"), value: 54)
            ],
            .hrv: [
                QuantitySample(id: "h1", kind: .hrv, start: at("2026-09-23 01:00"), end: at("2026-09-23 01:01"), value: 40),
                QuantitySample(id: "h2", kind: .hrv, start: at("2026-09-23 03:00"), end: at("2026-09-23 03:01"), value: 50),
                QuantitySample(id: "h3", kind: .hrv, start: at("2026-09-23 12:00"), end: at("2026-09-23 12:01"), value: 90)
            ]
        ]
        let v = NightVitals.compute(night: night, samples: samples, heartRate: nil)
        #expect(v.restingHeartRate == 54)
        #expect(v.hrv == 45)
    }

    @Test("До 7 ночей — только окно сна")
    func forecastWindowOnly() {
        let n = NightBuilder.build(samples: nights(count: 5, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: 23 * 60, wake: 7 * 60, inBed: true, latency: 15)
        }, defaultTimeZone: moscow).nights
        let model = ForecastModel.build(nights: n, goalMinutes: 450, regularity: nil)
        let f = model.forecast(bedtime: at("2026-09-30 23:00"), wake: at("2026-10-01 07:00"))
        #expect(f.windowMinutes == 480)
        #expect(f.predictedMinutes.isNone)
    }

    @Test("Десять ночей недостаточно для проверенного прогноза")
    func forecastDuration() {
        let n = NightBuilder.build(samples: nights(count: 10, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: 23 * 60, wake: 7 * 60, inBed: true, latency: 15, awake: 10)
        }, defaultTimeZone: moscow).nights
        let model = ForecastModel.build(nights: n, goalMinutes: 450, regularity: 90)
        #expect(num(model.medianLatency) == 15)
        #expect(num(model.medianAwake) == 10)
        let f = model.forecast(bedtime: at("2026-09-30 23:00"), wake: at("2026-10-01 07:00"))
        #expect(f.predictedMinutes == nil)
        #expect(f.balanceChangeMinutes == nil)
        #expect(f.latencyKnown)
    }

    @Test("Без данных «в кровати» длительность не прогнозируется")
    func forecastWithoutInBed() {
        let n = NightBuilder.build(samples: nights(count: 8, lastWakeDay: day("2026-09-30")) { _, e in
            simpleNight(evening: e, bed: 23 * 60, wake: 7 * 60)
        }, defaultTimeZone: moscow).nights
        let f = ForecastModel.build(nights: n, goalMinutes: 450, regularity: nil)
            .forecast(bedtime: at("2026-09-30 23:00"), wake: at("2026-10-01 07:00"))
        #expect(f.predictedMinutes == nil)
        #expect(!f.latencyKnown)
    }

    @Test("После достаточной проверки есть диапазон длительности, но нет балла ночи")
    func forecastScoreAndRange() throws {
        let n = NightBuilder.build(samples: nights(count: 40, lastWakeDay: day("2026-09-30")) { i, e in
            simpleNight(evening: e, bed: 23 * 60 + (i % 3) * 10, wake: 7 * 60, inBed: true, latency: 10 + (i % 4) * 5, awake: 10)
        }, defaultTimeZone: moscow).nights
        let model = ForecastModel.build(nights: n, goalMinutes: 450, regularity: 90)
        #expect(model.canPredict)
        let f = model.forecast(bedtime: at("2026-09-30 23:00"), wake: at("2026-10-01 07:00"))
        let predicted = try #require(f.predictedMinutes)
        let low = try #require(f.lowMinutes)
        let high = try #require(f.highMinutes)
        #expect(low <= predicted && predicted <= high)
    }
}
