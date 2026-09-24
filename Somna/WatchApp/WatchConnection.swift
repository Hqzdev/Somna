import Foundation
import Combine
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnection: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var snapshot = WatchSnapshotStore.load()
    @Published private(set) var isConnected = false
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage: String?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func saveWake(minutes: Int, alarmEnabled: Bool) {
        guard isConnected else {
            errorMessage = "Для изменения будильника подключите iPhone"
            return
        }
        isSaving = true
        errorMessage = nil
        WCSession.default.sendMessage(
            ["wakeMinutes": minutes, "alarmEnabled": alarmEnabled],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    self?.accept(reply)
                    self?.isSaving = false
                }
            },
            errorHandler: { [weak self] _ in
                Task { @MainActor in
                    self?.errorMessage = "Не удалось связаться с iPhone. Попробуйте ещё раз."
                    self?.isSaving = false
                    self?.isConnected = WCSession.default.isReachable
                }
            }
        )
    }

    private func requestLatest() {
        guard isConnected else { return }
        WCSession.default.sendMessage(
            ["requestSnapshot": true],
            replyHandler: { [weak self] reply in
                Task { @MainActor in self?.accept(reply) }
            },
            errorHandler: { _ in }
        )
    }

    private func accept(_ payload: [String: Any]) {
        if let data = payload["snapshot"] as? Data,
           let value = try? PropertyListDecoder().decode(WatchSnapshot.self, from: data),
           value.updatedAt >= snapshot.updatedAt {
            snapshot = value
            WatchSnapshotStore.save(value)
            WidgetCenter.shared.reloadAllTimelines()
        }
        errorMessage = payload["error"] as? String
    }

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isConnected = activationState == .activated && session.isReachable
            self.accept(session.receivedApplicationContext)
            self.requestLatest()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isConnected = session.isReachable
            self.requestLatest()
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        Task { @MainActor in self.accept(applicationContext) }
    }
}
