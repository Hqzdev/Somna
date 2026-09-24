//
//  DemoHealthData.swift
//  SomnaCore
//
//  Debug builds only. Synthetic «Apple Health» records for the Simulator,
//  where there is no sleep data. They go through exactly the same pipeline
//  as real records (cache → NightBuilder → formulas). Never shipped.
//

#if DEBUG
import Foundation

nonisolated enum DemoHealthData {
    static let watchID = "demo.watch"
    static let phoneID = "demo.iphone"

    /// `nights` nights ending with the one that woke up on `lastWakeDay`.
    static func make(nights: Int = 45, lastWakeDay: DayKey, timeZone tz: TimeZone, seed: UInt64 = 7) -> HealthCache {
        var rng = SplitMix64(seed: seed)
        func uniform(_ lo: Double, _ hi: Double) -> Double {
            lo + (hi - lo) * Double(rng.next() % 10_000) / 10_000
        }
        var cache = HealthCache()
        var sleep: [SleepSample] = []
        var quantities: [QuantitySample] = []
        var workouts: [WorkoutSample] = []

        for i in 0..<nights {
            let wakeDay = lastWakeDay.adding(days: -(nights - 1 - i))
            let evening = wakeDay.adding(days: -1)
            // Habits of the evening before.
            let lateCaffeine = rng.next() % 10 < 3
            let workout = rng.next() % 10 < 4
            let lateWorkout = workout && rng.next() % 2 == 0
            let daylight = uniform(5, 80)

            let bed = Int(uniform(23 * 60 - 10, 24 * 60 + 30)) + (lateCaffeine ? 25 : 0)
            let wake = Int(uniform(6 * 60 + 50, 7 * 60 + 40))
            let latency = Int(uniform(8, 22)) + (lateCaffeine ? 20 : 0)
            let inBedStart = evening.date(atMinutes: bed - latency, in: tz)
            let sleepStart = evening.date(atMinutes: bed, in: tz)
            let wakeDate = evening.date(atMinutes: wake + 1440, in: tz)

            sleep.append(SleepSample(id: "demo-bed-\(i)", start: inBedStart, end: wakeDate.addingTimeInterval(6 * 60),
                                     stage: .inBed, sourceID: watchID, sourceName: "Apple Watch", timeZoneID: tz.identifier))

            // ~90-minute cycles: core → deep (early) → core → REM, short awakenings.
            var t = sleepStart
            var cycle = 0
            while t < wakeDate {
                let parts: [(SleepStage, Double)] = [
                    (.core, uniform(20, 35)),
                    (.deep, cycle < 2 ? uniform(25, 45) : uniform(0, 12)),
                    (.core, uniform(15, 30)),
                    (.rem, cycle < 2 ? uniform(10, 20) : uniform(20, 35)),
                    (.awake, rng.next() % 3 == 0 ? uniform(2, 9) : 0)
                ]
                for (stage, minutes) in parts where minutes >= 1 {
                    let end = min(t.addingTimeInterval(minutes * 60), wakeDate)
                    guard end > t else { break }
                    sleep.append(SleepSample(id: "demo-\(i)-\(sleep.count)", start: t, end: end, stage: stage,
                                             sourceID: watchID, sourceName: "Apple Watch", timeZoneID: tz.identifier))
                    t = end
                }
                cycle += 1
            }

            let hrvBase = 48 - (lateCaffeine ? 6 : 0) - (lateWorkout ? 4 : 0)
            for k in 0..<4 {
                let at = sleepStart.addingTimeInterval(Double(k + 1) * 5400)
                guard at < wakeDate else { continue }
                quantities.append(QuantitySample(id: "demo-hrv-\(i)-\(k)", kind: .hrv, start: at,
                                                 end: at.addingTimeInterval(60), value: Double(hrvBase) + uniform(-7, 7),
                                                 sourceID: watchID))
                quantities.append(QuantitySample(id: "demo-resp-\(i)-\(k)", kind: .respiratoryRate, start: at,
                                                 end: at.addingTimeInterval(60), value: uniform(13.6, 15.4), sourceID: watchID))
                quantities.append(QuantitySample(id: "demo-spo2-\(i)-\(k)", kind: .oxygenSaturation, start: at,
                                                 end: at.addingTimeInterval(60), value: uniform(95.5, 98.5), sourceID: watchID))
            }
            let rhrAt = wakeDay.date(atMinutes: 20 * 60, in: tz)
            quantities.append(QuantitySample(id: "demo-rhr-\(i)", kind: .restingHeartRate, start: rhrAt, end: rhrAt,
                                             value: 54 + uniform(-3, 3) + (lateCaffeine ? 2 : 0), sourceID: watchID))
            quantities.append(QuantitySample(id: "demo-temp-\(i)", kind: .wristTemperature, start: sleepStart, end: wakeDate,
                                             value: 35.9 + uniform(-0.25, 0.25), sourceID: watchID))
            let caffeineAt = evening.date(atMinutes: lateCaffeine ? 16 * 60 + 30 : 9 * 60, in: tz)
            quantities.append(QuantitySample(id: "demo-caf-\(i)", kind: .caffeine, start: caffeineAt, end: caffeineAt,
                                             value: 95, sourceID: phoneID))
            quantities.append(QuantitySample(id: HealthCache.dailyID(.daylight, evening), kind: .daylight,
                                             start: evening.startDate(in: tz), end: evening.adding(days: 1).startDate(in: tz),
                                             value: daylight.rounded(), sourceID: watchID))
            quantities.append(QuantitySample(id: HealthCache.dailyID(.steps, evening), kind: .steps,
                                             start: evening.startDate(in: tz), end: evening.adding(days: 1).startDate(in: tz),
                                             value: uniform(4_000, 14_000).rounded(), sourceID: watchID))
            if workout {
                let start = evening.date(atMinutes: lateWorkout ? 20 * 60 : 18 * 60, in: tz)
                workouts.append(WorkoutSample(id: "demo-w-\(i)", start: start, end: start.addingTimeInterval(45 * 60),
                                              activityName: "Бег"))
            }
            cache.heartRate[wakeDay.description] = NightHeartRate(average: 57 + uniform(-3, 4), minimum: 49 + uniform(-3, 3))
        }
        cache.applySleep(added: sleep, deleted: [])
        cache.applyQuantities(added: quantities, deleted: [])
        cache.applyWorkouts(added: workouts, deleted: [])
        return cache
    }
}
#endif
