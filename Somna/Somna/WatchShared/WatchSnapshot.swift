import Foundation

/// The small, privacy-conscious projection shared with the paired watch.
struct WatchSnapshot: Codable, Equatable, Sendable {
    var updatedAt: Date
    var timeZoneID: String
    var sleepEnd: Date?
    var sleepScore: Int?
    var sleepMinutes: Int?
    var deepMinutes: Int?
    var remMinutes: Int?
    var goalMinutes: Int
    var bedtimeMinutes: Int
    var wakeMinutes: Int
    var alarmEnabled: Bool
    var planAction: String?

    static let empty = WatchSnapshot(
        updatedAt: .distantPast,
        timeZoneID: TimeZone.current.identifier,
        sleepEnd: nil,
        sleepScore: nil,
        sleepMinutes: nil,
        deepMinutes: nil,
        remMinutes: nil,
        goalMinutes: 450,
        bedtimeMinutes: 23 * 60,
        wakeMinutes: 7 * 60 + 30,
        alarmEnabled: false,
        planAction: nil
    )

    func hasRecentSleep(at date: Date) -> Bool {
        guard let sleepEnd else { return false }
        return date.timeIntervalSince(sleepEnd) < 48 * 60 * 60
    }

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(updatedAt) > 36 * 60 * 60 || timeZoneID != TimeZone.current.identifier
    }

    static func clock(_ minutes: Int) -> String {
        let value = (minutes % 1440 + 1440) % 1440
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    static func duration(_ minutes: Int) -> String {
        "\(minutes / 60) ч \(minutes % 60) мин"
    }
}
