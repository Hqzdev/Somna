//
//  TestSupport.swift
//  SomnaCoreTests
//
//  Fixed inputs: every date is written as local clock time in a known zone.
//

import Foundation
@testable import SomnaCore

let moscow = TimeZone(identifier: "Europe/Moscow")!

/// "2026-09-22 23:10" in `tz`.
func at(_ text: String, _ tz: TimeZone = moscow) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = tz
    f.dateFormat = "yyyy-MM-dd HH:mm"
    guard let d = f.date(from: text) else { fatalError("bad date \(text)") }
    return d
}

func day(_ text: String) -> DayKey { DayKey(string: text)! }

func sample(_ start: String, _ end: String, _ stage: SleepStage,
            source: String = "watch", name: String? = nil, tz: TimeZone = moscow) -> SleepSample {
    return SleepSample(id: UUID().uuidString, start: at(start, tz), end: at(end, tz),
                       stage: stage, sourceID: source, sourceName: name ?? source, timeZoneID: tz.identifier)
}

/// A simple night: core sleep from `bed` to `wake` on the given evening/morning.
func simpleNight(evening: DayKey, bed: Int, wake: Int, source: String = "watch",
                 inBed: Bool = false, latency: Int = 0, awake: Int = 0, tz: TimeZone = moscow) -> [SleepSample] {
    let bedDate = evening.date(atMinutes: bed, in: tz)
    let wakeDate = evening.date(atMinutes: wake + 1440, in: tz)
    var out: [SleepSample] = []
    let id = UUID().uuidString
    if inBed {
        out.append(SleepSample(id: "\(id)-bed", start: bedDate.addingTimeInterval(-Double(latency) * 60), end: wakeDate,
                               stage: .inBed, sourceID: source, sourceName: source, timeZoneID: tz.identifier))
    }
    if awake > 0 {
        let mid = bedDate.addingTimeInterval(wakeDate.timeIntervalSince(bedDate) / 2)
        out.append(SleepSample(id: "\(id)-c1", start: bedDate, end: mid, stage: .core,
                               sourceID: source, sourceName: source, timeZoneID: tz.identifier))
        let afterAwake = mid.addingTimeInterval(Double(awake) * 60)
        out.append(SleepSample(id: "\(id)-aw", start: mid, end: afterAwake, stage: .awake,
                               sourceID: source, sourceName: source, timeZoneID: tz.identifier))
        out.append(SleepSample(id: "\(id)-c2", start: afterAwake, end: wakeDate, stage: .core,
                               sourceID: source, sourceName: source, timeZoneID: tz.identifier))
    } else {
        out.append(SleepSample(id: "\(id)-c", start: bedDate, end: wakeDate, stage: .core,
                               sourceID: source, sourceName: source, timeZoneID: tz.identifier))
    }
    return out
}

/// `count` nights ending on `lastWakeDay`, each built by `make(index, evening)`.
func nights(count: Int, lastWakeDay: DayKey, _ make: (Int, DayKey) -> [SleepSample]) -> [SleepSample] {
    (0..<count).flatMap { i -> [SleepSample] in
        let wakeDay = lastWakeDay.adding(days: -(count - 1 - i))
        return make(i, wakeDay.adding(days: -1))
    }
}

func input(samples: [SleepSample], now: String = "2026-09-30 20:00") -> SomnaInput {
    var i = SomnaInput()
    i.sleepSamples = samples
    i.now = at(now)
    i.timeZone = moscow
    return i
}

/// Unwraps for comparisons inside #expect (optional Double comparisons crash
/// the 6.1 compiler in macro expansion); nil becomes NaN and never matches.
func num(_ value: Double?) -> Double { value ?? .nan }

extension Optional {
    var isNone: Bool {
        if case .none = self { return true }
        return false
    }
}
