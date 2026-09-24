//
//  QuickActions.swift
//  Somna
//
//  Home Screen quick actions — the menu on a long press on the app icon.
//  The list is rebuilt after every recompute and when the app goes to the
//  background, so subtitles carry tonight's times and the order follows the
//  time of day: morning — check-in and the night, evening — wind-down and plan.
//

import SwiftUI
import UIKit

nonisolated enum QuickAction: String, CaseIterable, Sendable {
    case checkIn = "yaroslavstrelkov.Somna.checkIn"
    case night = "yaroslavstrelkov.Somna.night"
    case plan = "yaroslavstrelkov.Somna.plan"
    case windDown = "yaroslavstrelkov.Somna.windDown"
    case alarm = "yaroslavstrelkov.Somna.alarm"
}

/// Hands a tapped action from UIKit to the SwiftUI tree.
@Observable
final class QuickActionRouter {
    static let shared = QuickActionRouter()
    var pending: QuickAction?
}

// MARK: - UIKit entry points

final class SomnaAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Cold launch from a quick action.
        if let item = options.shortcutItem, let action = QuickAction(rawValue: item.type) {
            QuickActionRouter.shared.pending = action
        }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SomnaSceneDelegate.self
        return configuration
    }
}

final class SomnaSceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The app was already running.
    func windowScene(_ windowScene: UIWindowScene,
                     performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        guard let action = QuickAction(rawValue: shortcutItem.type) else {
            completionHandler(false)
            return
        }
        QuickActionRouter.shared.pending = action
        completionHandler(true)
    }
}

// MARK: - Menu contents

enum QuickActions {
    static func update(store: SomnaStore, now: Date = Date()) {
        guard store.hasLoaded, store.isOnboarded else {
            UIApplication.shared.shortcutItems = []
            return
        }
        let snapshot = store.snapshot
        let plan = snapshot.plan
        let bedtime = Fmt.clock(plan.bedtimeMinutes)
        let wake = Fmt.clock(plan.wakeMinutes)
        let windDown = plan.actions.first { $0.kind == .screenOff }?.minutes.map { Fmt.clock($0) }
        let latest = snapshot.latest
        let checkedIn = latest.map { store.checkIn(for: $0.dayKey) != nil } ?? false
        var nightText = "Ночь пока не записана"
        if let report = latest {
            var parts: [String] = []
            if let score = report.score { parts.append("Оценка \(score.value)") }
            parts.append(Fmt.duration(report.night.asleepMinutes))
            nightText = parts.joined(separator: " · ")
        }

        let checkIn = item(.checkIn, "Утренняя отметка",
                           checkedIn ? "Отмечено · можно изменить" : "Как вы спали — 10 секунд", "sun.max")
        let night = item(.night, "Разбор ночи", nightText, "moon.stars")
        let planItem = item(.plan, "План на вечер", "Лечь в \(bedtime)", "list.bullet")
        let windDownItem = item(.windDown, "Вечерний режим",
                                windDown.map { "Без экрана с \($0)" } ?? "Лечь в \(bedtime)", "moon")
        let alarm = item(.alarm, "Будильник",
                         store.settings.alarmEnabled ? "Подъём в \(wake)" : "Выключен", "alarm")

        let hour = Calendar.current.component(.hour, from: now)
        let isMorning = (5..<15).contains(hour)
        UIApplication.shared.shortcutItems = isMorning
            ? [checkIn, night, planItem, alarm]
            : [windDownItem, planItem, alarm, night]
    }

    private static func item(_ action: QuickAction, _ title: String, _ subtitle: String?,
                             _ systemImage: String) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(type: action.rawValue,
                                  localizedTitle: title,
                                  localizedSubtitle: subtitle,
                                  icon: UIApplicationShortcutIcon(systemImageName: systemImage),
                                  userInfo: nil)
    }
}

// MARK: - Routing

extension AppState {
    func perform(_ action: QuickAction) {
        sheet = nil
        cover = nil
        switch action {
        case .checkIn:
            go(to: .today)
            sheet = .checkIn
        case .night:
            selectedNight = nil
            go(to: .sleep)
        case .plan:
            planPath = [.eveningPlan]
            go(to: .plan, reset: false)
        case .windDown:
            planPath = [.eveningPlan]
            go(to: .plan, reset: false)
            cover = .windDown
        case .alarm:
            sheet = .alarm
        }
    }
}
