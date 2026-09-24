//
//  AppState.swift
//  Somna
//
//  Navigation and interface state only. Data and results live in SomnaStore
//  (persisted on this iPhone) and SomnaCore (formulas).
//

import SwiftUI
import Observation
import Foundation

// MARK: - Navigation

nonisolated enum AppTab: Hashable, CaseIterable {
    case today, sleep, plan, journal, profile
}

nonisolated enum AppRoute: Hashable {
    case nightReview(DayKey)
    case factors
    case sleepDebt
    case environment
    case circadian
    case healthSignals
    case eveningPlan
    case insights
    case experimentSetup
    case experimentProgress
    case experimentResults(String)
    case dataSources
}

nonisolated enum SheetRoute: String, Identifiable {
    case checkIn
    case whyPlan
    case customFactor
    case profileAnswers
    case sleepGoal
    case alarm

    var id: String { rawValue }
}

nonisolated enum CoverRoute: String, Identifiable {
    case windDown

    var id: String { rawValue }
}

// MARK: - App state

@Observable
final class AppState {
    var tab: AppTab = .today
    var todayPath: [AppRoute] = []
    var sleepPath: [AppRoute] = []
    var planPath: [AppRoute] = []
    var journalPath: [AppRoute] = []
    var profilePath: [AppRoute] = []
    var sheet: SheetRoute?
    var cover: CoverRoute?
    var toast: String?

    /// Debug control: preview another time of day.
    var timeOverride: TimeOfDay?
    /// Bedtime picked on the forecast for tonight (minutes after midnight, may exceed 1440).
    var plannedBedtime: Int?
    /// Night shown in the «Сон» tab root; nil = the latest one.
    var selectedNight: DayKey?
    /// Factor to preselect on the experiment setup screen.
    var experimentFactorID: String?

    // MARK: Derived

    var timeOfDay: TimeOfDay {
        if let timeOverride { return timeOverride }
        return TimeOfDay.at(hour: Calendar.current.component(.hour, from: Date()))
    }

    /// Theme used by evening screens: dusk before 21:00, night after.
    var forecastMode: TimeOfDay {
        timeOfDay == .night ? .night : .dusk
    }

    /// Mode of whatever is on screen right now — drives status bar and tab bar.
    var activeMode: TimeOfDay {
        if cover != nil { return .night }
        switch tab {
        case .plan:
            return planPath.contains(.eveningPlan) ? .night : forecastMode
        default:
            return timeOfDay
        }
    }

    // MARK: Actions

    func go(to tab: AppTab, reset: Bool = true) {
        if reset { setPath([], for: tab) }
        self.tab = tab
    }

    func push(_ route: AppRoute) {
        switch tab {
        case .today: todayPath.append(route)
        case .sleep: sleepPath.append(route)
        case .plan: planPath.append(route)
        case .journal: journalPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    func setPath(_ path: [AppRoute], for tab: AppTab) {
        switch tab {
        case .today: todayPath = path
        case .sleep: sleepPath = path
        case .plan: planPath = path
        case .journal: journalPath = path
        case .profile: profilePath = path
        }
    }

    func resetNavigation() {
        for t in AppTab.allCases { setPath([], for: t) }
        tab = .today
        sheet = nil
        cover = nil
        plannedBedtime = nil
        selectedNight = nil
    }

    func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.6))
            if self.toast == text {
                withAnimation(.easeIn(duration: 0.2)) { self.toast = nil }
            }
        }
    }
}
