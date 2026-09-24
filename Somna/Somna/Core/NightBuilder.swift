//
//  NightBuilder.swift
//  SomnaCore
//
//  Raw sleep samples → nights.
//
//  1. Within one source, overlapping samples are resolved by specificity
//     (measured stages over «asleep, unspecified»).
//  2. Episodes: a source's asleep intervals separated by gaps of up to
//     90 minutes are one episode.
//  3. Duplicates: when episodes of different sources overlap, the episode of
//     the highest-priority source is used for the whole sleep — sources are
//     never summed or stitched together inside one night.
//  4. The main sleep of a local wake day is the episode with the most sleep;
//     other episodes of that day are naps.
//  5. Sleep time counts asleep intervals only; awake is counted separately.
//     «In bed» may overlap stages, so it is never added to sleep time.
//     Missing stage boundaries are not invented: gaps without data are
//     neither sleep nor wake.
//

import Foundation

nonisolated struct StageDurations: Codable, Hashable, Sendable {
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var unspecified: TimeInterval = 0

    var hasDetailedStages: Bool { core + deep + rem > 0 }
}

nonisolated enum MeasurementStatus: String, Codable, Hashable, Sendable {
    case measured, approximate, missing, contradictory
}

nonisolated struct NightMeasurement: Codable, Hashable, Sendable {
    var value: Double?
    var status: MeasurementStatus
    var sourceID: String?
    var measuredAt: Date?
    var refreshedAt: Date? = nil
}

nonisolated struct NightMeasurementReport: Codable, Hashable, Sendable {
    var asleep: NightMeasurement
    var timeInBed: NightMeasurement
    var latency: NightMeasurement
    var wakeAfterOnset: NightMeasurement
    var awakeningsOverFive: NightMeasurement
    var efficiency: NightMeasurement
    var detailedStageCoverage: NightMeasurement
    var unknownMinutes: NightMeasurement

    func refreshed(at date: Date?) -> NightMeasurementReport {
        var copy = self
        copy.asleep.refreshedAt = date
        copy.timeInBed.refreshedAt = date
        copy.latency.refreshedAt = date
        copy.wakeAfterOnset.refreshedAt = date
        copy.awakeningsOverFive.refreshedAt = date
        copy.efficiency.refreshedAt = date
        copy.detailedStageCoverage.refreshedAt = date
        copy.unknownMinutes.refreshedAt = date
        return copy
    }
}

nonisolated struct SleepNight: Codable, Hashable, Sendable, Identifiable {
    /// Local day of waking up.
    var dayKey: DayKey
    var timeZoneID: String
    /// First asleep moment.
    var sleepStart: Date
    /// End of the last asleep interval.
    var sleepEnd: Date
    /// From «in bed» samples, when a source recorded them.
    var inBedStart: Date?
    var inBedEnd: Date?
    /// Asleep time (all asleep stages).
    var asleep: TimeInterval
    /// Recorded awake time inside the sleep period.
    var awake: TimeInterval
    /// Recorded awakenings inside the sleep period.
    var awakenings: Int
    var stages: StageDurations
    /// Union of «in bed» with the sleep period, when «in bed» exists.
    var timeInBed: TimeInterval?
    /// Painted asleep and awake intervals for the hypnogram.
    var intervals: [SleepInterval]
    var sourceIDs: [String]
    /// True when this night's time zone differs from the previous night's.
    var timeZoneChanged: Bool

    var id: String { dayKey.description }

    /// Nights shorter than 3 h of sleep are kept but not used for baselines.
    static let minimumValidSleep: TimeInterval = 3 * 3600

    var isValid: Bool { asleep >= Self.minimumValidSleep }

    var timeZone: TimeZone { SomnaCalendar.zone(timeZoneID, fallback: .current) }

    var asleepMinutes: Double { asleep / 60 }

    /// The winning sleep source; in-bed samples must come from this source.
    var primarySourceID: String? { intervals.first(where: { $0.stage.isAsleep })?.sourceID }

    /// Unclassified time between sleep stages and after the final stage while still in bed.
    var unknownMinutes: Double {
        let internalGap = max(0, sleepEnd.timeIntervalSince(sleepStart) - asleep - awake)
        let trailingGap = max(0, inBedEnd?.timeIntervalSince(sleepEnd) ?? 0)
        return (internalGap + trailingGap) / 60
    }

    var awakeningsOverFiveMinutes: Int {
        var stretches: [(Date, Date)] = []
        for interval in intervals.filter({ $0.stage == .awake }).sorted(by: { $0.start < $1.start }) {
            if let last = stretches.indices.last, interval.start.timeIntervalSince(stretches[last].1) < 60 {
                stretches[last].1 = max(stretches[last].1, interval.end)
            } else {
                stretches.append((interval.start, interval.end))
            }
        }
        return stretches.filter { $0.1.timeIntervalSince($0.0) >= 5 * 60 }.count
    }

    var detailedStageCoverage: Double {
        guard asleep > 0 else { return 0 }
        return min(1, (stages.core + stages.deep + stages.rem) / asleep)
    }

    var measurements: NightMeasurementReport {
        let source = primarySourceID
        func item(_ value: Double?, _ status: MeasurementStatus) -> NightMeasurement {
            NightMeasurement(value: value, status: value == nil ? .missing : status,
                             sourceID: source, measuredAt: value == nil ? nil : sleepEnd)
        }
        let complete = continuityIsReliable
        let wakeStatus: MeasurementStatus = unknownMinutes > 20 ? .contradictory : (complete ? .measured : .approximate)
        let envelopeCoversSleep = inBedStart.map { $0 <= sleepStart } == true
            && inBedEnd.map { $0 >= sleepEnd } == true
        let inBedStatus: MeasurementStatus = timeInBed == nil ? .missing
            : (!envelopeCoversSleep || (timeInBed ?? 0) < asleep ? .contradictory : .measured)
        return NightMeasurementReport(
            asleep: item(asleepMinutes, .measured),
            timeInBed: item(timeInBed.map { $0 / 60 }, inBedStatus),
            latency: item(latencyMinutes, complete ? .approximate : .contradictory),
            wakeAfterOnset: item(stages.hasDetailedStages || intervals.contains(where: { $0.stage == .awake }) ? awake / 60 : nil, wakeStatus),
            awakeningsOverFive: item(stages.hasDetailedStages || intervals.contains(where: { $0.stage == .awake }) ? Double(awakeningsOverFiveMinutes) : nil, wakeStatus),
            efficiency: item(efficiency, complete ? .approximate : .contradictory),
            detailedStageCoverage: item(stages.hasDetailedStages ? detailedStageCoverage : nil, .measured),
            unknownMinutes: item(unknownMinutes, .measured))
    }

    var continuityIsReliable: Bool {
        guard let timeInBed, timeInBed >= asleep, let inBedStart, let inBedEnd,
              inBedStart <= sleepStart, inBedEnd >= sleepEnd,
              stages.hasDetailedStages || intervals.contains(where: { $0.stage == .awake }) else { return false }
        return unknownMinutes <= 20 && unknownMinutes <= timeInBed / 60 * 0.10
    }

    /// Minutes from getting into bed to falling asleep; needs «in bed» data.
    var latencyMinutes: Double? {
        guard let inBedStart, inBedStart <= sleepStart else { return nil }
        return sleepStart.timeIntervalSince(inBedStart) / 60
    }

    /// Asleep ÷ time in bed, 0…1; needs «in bed» data.
    var efficiency: Double? {
        guard let timeInBed, timeInBed > 0 else { return nil }
        return min(1, asleep / timeInBed)
    }

    /// Sleep onset on the noon-to-noon scale (local clock).
    var bedtimeScale: Double { ClockTime.bedtimeScale(sleepStart, in: timeZone) }
    /// Wake time, minutes after local midnight.
    var wakeScale: Double { ClockTime.wakeScale(sleepEnd, in: timeZone) }
}

nonisolated struct NapSummary: Codable, Hashable, Sendable {
    var dayKey: DayKey
    var start: Date
    var end: Date
    var asleep: TimeInterval
}

nonisolated struct SleepHistory: Sendable {
    /// One main sleep per wake day, sorted by day.
    var nights: [SleepNight]
    var naps: [NapSummary]
    /// Detected sources with their effective rank (0 = highest).
    var sourceRanking: [String: Int]

    static let empty = SleepHistory(nights: [], naps: [], sourceRanking: [:])
}

nonisolated enum NightBuilder {
    /// Gaps up to this length join asleep intervals into one episode.
    static let maximumGap: TimeInterval = 90 * 60
    /// Painted pieces shorter than this are dropped as noise.
    static let minimumPiece: TimeInterval = 30

    static func build(samples: [SleepSample],
                      preferences: [SourcePreference] = [],
                      defaultTimeZone: TimeZone = .current) -> SleepHistory {
        let valid = samples.filter { $0.end > $0.start }
        guard !valid.isEmpty else { return .empty }

        let ranking = sourceRanking(samples: valid, preferences: preferences)
        // Paint in-bed envelopes separately for each source. Painting all
        // sources together would erase the chosen source where devices overlap.
        let inBed = Dictionary(grouping: valid.filter { $0.stage == .inBed }, by: \.sourceID)
            .values.flatMap { paint($0, ranking: ranking) }
        let zoneBySample = timeZoneLookup(valid, fallback: defaultTimeZone)

        // Episodes per source, then one winner per group of overlapping episodes.
        var sourceEpisodes: [Episode] = []
        let bySource = Dictionary(grouping: valid.filter { $0.stage != .inBed }, by: \.sourceID)
        for (sourceID, list) in bySource {
            let pieces = paint(list, ranking: ranking)
            for var e in makeEpisodes(pieces) {
                e.rank = ranking[sourceID] ?? Int.max
                sourceEpisodes.append(e)
            }
        }
        let episodes = resolveOverlaps(sourceEpisodes)
        var mainByDay: [DayKey: Episode] = [:]
        var napEpisodes: [(DayKey, Episode)] = []

        for episode in episodes {
            let zone = zoneBySample(episode.lastAsleep)
            let day = DayKey(date: Date(timeIntervalSinceReferenceDate: episode.end), timeZone: zone)
            if let current = mainByDay[day] {
                let better = episode.asleep > current.asleep
                    || (episode.asleep == current.asleep && episode.end > current.end)
                if better {
                    napEpisodes.append((day, current))
                    mainByDay[day] = episode
                } else {
                    napEpisodes.append((day, episode))
                }
            } else {
                mainByDay[day] = episode
            }
        }

        var nights: [SleepNight] = []
        for day in mainByDay.keys.sorted() {
            guard let episode = mainByDay[day] else { continue }
            let zone = zoneBySample(episode.lastAsleep)
            nights.append(makeNight(day: day, zone: zone, episode: episode, inBed: inBed))
        }
        for i in nights.indices where i > 0 {
            nights[i].timeZoneChanged = nights[i].timeZoneID != nights[i - 1].timeZoneID
        }

        let naps = napEpisodes
            .map { NapSummary(dayKey: $0.0,
                              start: Date(timeIntervalSinceReferenceDate: $0.1.start),
                              end: Date(timeIntervalSinceReferenceDate: $0.1.end),
                              asleep: $0.1.asleep) }
            .sorted { $0.start < $1.start }
        return SleepHistory(nights: nights, naps: naps, sourceRanking: ranking)
    }

    // MARK: Source ranking

    /// Explicit preferences first (by priority), then detected sources:
    /// those with measured stages, then more samples, then by name.
    static func sourceRanking(samples: [SleepSample], preferences: [SourcePreference]) -> [String: Int] {
        var ranking: [String: Int] = [:]
        var next = 0
        for pref in preferences.sorted(by: { $0.priority < $1.priority }) where ranking[pref.sourceID] == nil {
            ranking[pref.sourceID] = next
            next += 1
        }
        var info: [String: SourceInfo] = [:]
        for s in samples {
            var i = info[s.sourceID] ?? SourceInfo(name: s.sourceName)
            if s.stage.isDetailedStage { i.detailed = true }
            if s.stage.isAsleep { i.count += 1 }
            info[s.sourceID] = i
        }
        let rest = info.filter { ranking[$0.key] == nil }.sorted { a, b in
            if a.value.detailed != b.value.detailed { return a.value.detailed }
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            if a.value.name != b.value.name { return a.value.name < b.value.name }
            return a.key < b.key
        }
        for (id, _) in rest {
            ranking[id] = next
            next += 1
        }
        return ranking
    }

    // MARK: Painting (duplicate resolution)

    static func paint(_ samples: [SleepSample], ranking: [String: Int]) -> [PaintedPiece] {
        let ordered = samples.sorted { a, b in
            let ra = ranking[a.sourceID] ?? Int.max
            let rb = ranking[b.sourceID] ?? Int.max
            if ra != rb { return ra < rb }
            if a.stage.specificity != b.stage.specificity { return a.stage.specificity > b.stage.specificity }
            if a.start != b.start { return a.start < b.start }
            return a.id < b.id
        }
        var covered = IntervalSet()
        var pieces: [PaintedPiece] = []
        for s in ordered {
            let s0 = s.start.timeIntervalSinceReferenceDate
            let s1 = s.end.timeIntervalSinceReferenceDate
            for part in covered.uncovered(s0, s1) where part.1 - part.0 >= minimumPiece {
                pieces.append(PaintedPiece(start: part.0, end: part.1, stage: s.stage,
                                           sourceID: s.sourceID, sampleID: s.id))
            }
            covered.insert(s0, s1)
        }
        return pieces.sorted { $0.start < $1.start }
    }

    // MARK: Episodes

    nonisolated struct Episode {
        var start: TimeInterval
        var end: TimeInterval
        var asleep: TimeInterval
        var pieces: [PaintedPiece]
        /// Sample id of the last asleep piece (time zone of waking up).
        var lastAsleep: String
        /// Rank of the episode's source (0 = highest priority).
        var rank: Int = Int.max
    }

    /// Groups episodes that overlap in time and keeps, for each group, the one
    /// from the highest-priority source (ties: more sleep).
    static func resolveOverlaps(_ episodes: [Episode]) -> [Episode] {
        let sorted = episodes.sorted { $0.start < $1.start }
        var result: [Episode] = []
        var group: [Episode] = []
        var groupEnd: TimeInterval = -.infinity
        func flush() {
            if let best = group.min(by: { a, b in
                a.rank != b.rank ? a.rank < b.rank : a.asleep > b.asleep
            }) {
                result.append(best)
            }
            group = []
        }
        for e in sorted {
            if !group.isEmpty && e.start >= groupEnd {
                flush()
            }
            group.append(e)
            groupEnd = group.count == 1 ? e.end : max(groupEnd, e.end)
        }
        flush()
        return result
    }

    static func makeEpisodes(_ detailed: [PaintedPiece]) -> [Episode] {
        let asleep = detailed.filter { $0.stage.isAsleep }
        guard let first = asleep.first else { return [] }
        var groups: [[PaintedPiece]] = [[first]]
        var groupEnd = first.end
        for p in asleep.dropFirst() {
            if p.start - groupEnd <= maximumGap {
                groups[groups.count - 1].append(p)
            } else {
                groups.append([p])
            }
            groupEnd = max(groupEnd, p.end)
        }
        return groups.map { g in
            let start = g.map(\.start).min() ?? 0
            let end = g.map(\.end).max() ?? 0
            let awake = detailed.filter { $0.stage == .awake && $0.end > start && $0.start < end }
            let last = g.max { $0.end < $1.end }
            return Episode(start: start, end: end,
                           asleep: g.reduce(0) { $0 + ($1.end - $1.start) },
                           pieces: (g + awake).sorted { $0.start < $1.start },
                           lastAsleep: last?.sampleID ?? "")
        }
    }

    static func makeNight(day: DayKey, zone: TimeZone, episode: Episode, inBed: [PaintedPiece]) -> SleepNight {
        var stages = StageDurations()
        var awake: TimeInterval = 0
        var awakenings = 0
        var intervals: [SleepInterval] = []
        var sources = Set<String>()
        for p in episode.pieces {
            let s = max(p.start, episode.start)
            let e = min(p.end, episode.end)
            guard e > s else { continue }
            let d = e - s
            switch p.stage {
            case .core: stages.core += d
            case .deep: stages.deep += d
            case .rem: stages.rem += d
            case .asleepUnspecified: stages.unspecified += d
            case .awake:
                awake += d
                awakenings += 1
            case .inBed: break
            }
            sources.insert(p.sourceID)
            intervals.append(SleepInterval(start: Date(timeIntervalSinceReferenceDate: s),
                                           end: Date(timeIntervalSinceReferenceDate: e),
                                           stage: p.stage, sourceID: p.sourceID))
        }
        // Adjacent awake pieces from different sources are one awakening.
        awakenings = countAwakenings(intervals)

        // Never attach a different device's in-bed envelope to the chosen episode.
        let sourceID = episode.pieces.first?.sourceID
        let near = inBed.filter {
            $0.sourceID == sourceID && $0.end >= episode.start - maximumGap && $0.start <= episode.end + maximumGap
        }
        var inBedStart: Date?
        var inBedEnd: Date?
        var timeInBed: TimeInterval?
        if !near.isEmpty {
            var union = IntervalSet()
            for p in near { union.insert(p.start, p.end) }
            let span = union.ranges.filter { $0.1 >= episode.start - maximumGap && $0.0 <= episode.end + maximumGap }
            if let lo = span.map(\.0).min(), let hi = span.map(\.1).max() {
                inBedStart = Date(timeIntervalSinceReferenceDate: lo)
                inBedEnd = Date(timeIntervalSinceReferenceDate: hi)
                timeInBed = span.reduce(0) { $0 + ($1.1 - $1.0) }
            }
            for p in near { sources.insert(p.sourceID) }
        }

        return SleepNight(dayKey: day,
                          timeZoneID: zone.identifier,
                          sleepStart: Date(timeIntervalSinceReferenceDate: episode.start),
                          sleepEnd: Date(timeIntervalSinceReferenceDate: episode.end),
                          inBedStart: inBedStart,
                          inBedEnd: inBedEnd,
                          asleep: episode.asleep,
                          awake: awake,
                          awakenings: awakenings,
                          stages: stages,
                          timeInBed: timeInBed,
                          intervals: intervals.sorted { $0.start < $1.start },
                          sourceIDs: sources.sorted(),
                          timeZoneChanged: false)
    }

    static func countAwakenings(_ intervals: [SleepInterval]) -> Int {
        var count = 0
        var lastAwakeEnd: Date?
        for i in intervals.sorted(by: { $0.start < $1.start }) where i.stage == .awake {
            if let last = lastAwakeEnd, i.start.timeIntervalSince(last) < 60 {
                lastAwakeEnd = max(last, i.end)
                continue
            }
            count += 1
            lastAwakeEnd = i.end
        }
        return count
    }

    /// Time zone of the sample, else the default.
    static func timeZoneLookup(_ samples: [SleepSample], fallback: TimeZone) -> (String) -> TimeZone {
        var zones: [String: TimeZone] = [:]
        for s in samples {
            if let id = s.timeZoneID, let tz = TimeZone(identifier: id) {
                zones[s.id] = tz
            }
        }
        return { id in zones[id] ?? fallback }
    }
}

nonisolated struct SourceInfo: Sendable {
    var name: String
    var detailed = false
    var count = 0
}

nonisolated struct PaintedPiece: Sendable {
    var start: TimeInterval
    var end: TimeInterval
    var stage: SleepStage
    var sourceID: String
    var sampleID: String
}

/// Sorted, non-overlapping [start, end) ranges on a time line.
nonisolated struct IntervalSet: Sendable {
    private(set) var ranges: [(TimeInterval, TimeInterval)] = []

    init() {}

    /// Parts of [s, e) that are not covered yet.
    func uncovered(_ s: TimeInterval, _ e: TimeInterval) -> [(TimeInterval, TimeInterval)] {
        guard e > s else { return [] }
        var result: [(TimeInterval, TimeInterval)] = []
        var cursor = s
        for (a, b) in ranges {
            if b <= cursor { continue }
            if a >= e { break }
            if a > cursor { result.append((cursor, min(a, e))) }
            cursor = max(cursor, b)
            if cursor >= e { break }
        }
        if cursor < e { result.append((cursor, e)) }
        return result
    }

    mutating func insert(_ s: TimeInterval, _ e: TimeInterval) {
        guard e > s else { return }
        var newStart = s
        var newEnd = e
        var kept: [(TimeInterval, TimeInterval)] = []
        var inserted = false
        for (a, b) in ranges {
            if b < newStart {
                kept.append((a, b))
            } else if a > newEnd {
                if !inserted {
                    kept.append((newStart, newEnd))
                    inserted = true
                }
                kept.append((a, b))
            } else {
                newStart = min(newStart, a)
                newEnd = max(newEnd, b)
            }
        }
        if !inserted { kept.append((newStart, newEnd)) }
        ranges = kept
    }

    var total: TimeInterval { ranges.reduce(0) { $0 + ($1.1 - $1.0) } }
}
