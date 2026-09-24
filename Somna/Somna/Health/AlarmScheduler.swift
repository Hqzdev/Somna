//
//  AlarmScheduler.swift
//  Somna
//
//  A plain daily alarm at the latest wake-up time, through AlarmKit (asks the
//  person for permission first). No sleep-phase wake-up is promised on
//  iPhone: that needs a future Apple Watch app sharing SomnaCore.
//

import Foundation
import SwiftUI
import AlarmKit

nonisolated struct SomnaAlarmMetadata: AlarmMetadata {}

@MainActor
enum AlarmScheduler {
    enum Outcome {
        case scheduled(UUID)
        case denied
        case failed(String)
    }

    /// Asks for permission if needed.
    static func authorize() async -> Bool {
        let manager = AlarmManager.shared
        switch manager.authorizationState {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let state = try? await manager.requestAuthorization()
            return state == .authorized
        @unknown default:
            return false
        }
    }

    /// Replaces the previous Somna alarm with one at `minutes` after midnight, every day.
    static func schedule(minutes: Int, replacing previous: UUID?) async -> Outcome {
        guard await authorize() else { return .denied }
        if let previous { await cancel(previous) }
        let alert = AlarmPresentation.Alert(
            title: "Пора вставать",
            stopButton: AlarmButton(text: "Встаю", textColor: .white, systemImageName: "sunrise"))
        let attributes = AlarmAttributes<SomnaAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SomnaAlarmMetadata(),
            tintColor: Brand.sunrise)
        let time = Alarm.Schedule.Relative.Time(hour: (minutes / 60) % 24, minute: minutes % 60)
        let schedule = Alarm.Schedule.relative(.init(time: time, repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])))
        let id = UUID()
        do {
            let configuration = AlarmManager.AlarmConfiguration(
                countdownDuration: nil,
                schedule: schedule,
                attributes: attributes,
                stopIntent: nil,
                secondaryIntent: nil)
            _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            return .scheduled(id)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func cancel(_ id: UUID) async {
        try? await AlarmManager.shared.cancel(id: id)
    }
}
