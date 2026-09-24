import Foundation

enum WatchSnapshotStore {
    static let groupID = "group.yaroslavstrelkov.Somna"
    private static let snapshotKey = "watchSnapshot"

    static func load() -> WatchSnapshot {
        guard let data = UserDefaults(suiteName: groupID)?.data(forKey: snapshotKey),
              let snapshot = try? PropertyListDecoder().decode(WatchSnapshot.self, from: data) else {
            return .empty
        }
        return snapshot
    }

    static func save(_ snapshot: WatchSnapshot) {
        guard let data = try? PropertyListEncoder().encode(snapshot) else { return }
        UserDefaults(suiteName: groupID)?.set(data, forKey: snapshotKey)
    }
}
