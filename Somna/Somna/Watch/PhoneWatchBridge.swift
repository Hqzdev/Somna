import Foundation
import WatchConnectivity

@MainActor
final class PhoneWatchBridge: NSObject, WCSessionDelegate {
    private weak var store: SomnaStore?

    init(store: SomnaStore) {
        self.store = store
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func publish() {
        guard let store, WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled,
              let data = try? PropertyListEncoder().encode(WatchSnapshot(store: store)) else { return }
        try? session.updateApplicationContext(["snapshot": data])
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in self.publish() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            guard let store = self.store, store.hasLoaded else {
                replyHandler(["error": "Данные Somna недоступны на iPhone"])
                return
            }

            if message["requestSnapshot"] as? Bool == true {
                replyHandler(self.response(for: store))
                return
            }

            guard let minutes = message["wakeMinutes"] as? Int,
                  (4 * 60...11 * 60 + 30).contains(minutes),
                  minutes.isMultiple(of: 5),
                  let enabled = message["alarmEnabled"] as? Bool else {
                replyHandler(["error": "Некорректное время подъёма"])
                return
            }

            await store.saveWake(minutes: minutes, alarm: enabled)
            self.publish()
            replyHandler(self.response(for: store))
        }
    }

    private func response(for store: SomnaStore) -> [String: Any] {
        var response: [String: Any] = [:]
        if let data = try? PropertyListEncoder().encode(WatchSnapshot(store: store)) {
            response["snapshot"] = data
        }
        if let message = store.alarmMessage {
            response["error"] = message
        }
        return response
    }
}

private extension WatchSnapshot {
    init(store: SomnaStore) {
        let snapshot = store.snapshot
        let night = snapshot.latest
        let stages = night?.night.stages
        self.init(
            updatedAt: Date(),
            timeZoneID: snapshot.timeZone.identifier,
            sleepEnd: night?.night.sleepEnd,
            sleepScore: night?.score?.value,
            sleepMinutes: night.map { Int($0.night.asleepMinutes.rounded()) },
            deepMinutes: stages?.hasDetailedStages == true ? stages.map { Int(($0.deep / 60).rounded()) } : nil,
            remMinutes: stages?.hasDetailedStages == true ? stages.map { Int(($0.rem / 60).rounded()) } : nil,
            goalMinutes: store.settings.goalMinutes,
            bedtimeMinutes: snapshot.plan.bedtimeMinutes,
            wakeMinutes: store.settings.wakeMinutes ?? snapshot.wakeMinutes,
            alarmEnabled: store.settings.alarmEnabled,
            planAction: snapshot.plan.actions.first?.title
        )
    }
}
