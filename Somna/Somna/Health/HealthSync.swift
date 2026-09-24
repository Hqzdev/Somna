//
//  HealthSync.swift
//  Somna
//
//  Brings the local cache up to date with Apple Health: new, edited and
//  deleted records since the last anchors, daily totals and heart rate
//  during recent nights. Runs off the main thread.
//

import Foundation
import HealthKit

nonisolated enum HealthSync {
    /// Heart rate is kept for this many recent nights.
    static let heartRateNights = 45

    static func refresh(_ current: HealthCache, reader: HealthKitReader,
                        now: Date, timeZone: TimeZone) async throws -> HealthCache {
        var cache = current
        let since = now.addingTimeInterval(-Double(HealthCache.historyDays) * 86_400)

        let sleep = try await reader.fetchSleep(anchor: HealthKitReader.unarchive(cache.anchors["sleep"]), since: since)
        cache.applySleep(added: sleep.added, deleted: sleep.deleted)
        cache.anchors["sleep"] = HealthKitReader.archive(sleep.anchor)

        // Each type is independent: a type without permission simply returns nothing.
        for kind in reader.sampledKinds {
            let anchor = HealthKitReader.unarchive(cache.anchors[kind.rawValue])
            if let r = try? await reader.fetchQuantities(kind: kind, anchor: anchor, since: since) {
                cache.applyQuantities(added: r.added, deleted: r.deleted)
                cache.anchors[kind.rawValue] = HealthKitReader.archive(r.anchor)
            }
        }

        if let w = try? await reader.fetchWorkouts(anchor: HealthKitReader.unarchive(cache.anchors["workouts"]), since: since) {
            cache.applyWorkouts(added: w.added, deleted: w.deleted)
            cache.anchors["workouts"] = HealthKitReader.archive(w.anchor)
        }

        // Daily totals settle within a couple of weeks; refetch that part each time.
        let dailySince = cache.lastSync == nil ? since : now.addingTimeInterval(-14 * 86_400)
        if let totals = try? await reader.fetchDailyTotals(since: dailySince, until: now, timeZone: timeZone) {
            cache.upsertDailyTotals(totals)
        }

        cache.prune(before: since)

        // Heart rate during the main sleep of recent nights (the last two are
        // refreshed every time, they may still be growing).
        let nights = NightBuilder.build(samples: Array(cache.sleep.values), defaultTimeZone: timeZone).nights
        let recent = nights.suffix(heartRateNights)
        let keep = Set(recent.map(\.id))
        cache.heartRate = cache.heartRate.filter { keep.contains($0.key) }
        for (index, night) in recent.enumerated() {
            let isFresh = index >= recent.count - 2
            guard cache.heartRate[night.id] == nil || isFresh else { continue }
            if let hr = try? await reader.nightHeartRate(from: night.sleepStart, to: night.sleepEnd) {
                cache.heartRate[night.id] = hr
            }
        }

        cache.lastSync = now
        return cache
    }
}

/// The cache lives in one JSON file, protected by iOS data protection.
nonisolated enum HealthCacheFile {
    static var url: URL {
        URL.applicationSupportDirectory
            .appending(path: "Somna", directoryHint: .isDirectory)
            .appending(path: "health-cache.json", directoryHint: .notDirectory)
    }

    static func load() -> HealthCache? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(HealthCache.self, from: data),
              cache.version == HealthCache.schemaVersion else { return nil }
        return cache
    }

    static func save(_ cache: HealthCache) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(cache)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // The cache can always be rebuilt from Apple Health.
        }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: url)
    }
}
