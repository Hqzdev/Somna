//
//  RootTabView.swift
//  Somna
//
//  Five-tab shell. The native iOS tab bar supplies Liquid Glass;
//  each tab owns a typed NavigationStack path in AppState.
//

import SwiftUI
import Foundation

struct RootTabView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        TabView(selection: $state.tab) {
            Tab("Сегодня", systemImage: "sunrise", value: AppTab.today) {
                NavigationStack(path: $state.todayPath) {
                    TodayView()
                        .routeDestinations()
                }
            }

            Tab("Сон", systemImage: "moon", value: AppTab.sleep) {
                NavigationStack(path: $state.sleepPath) {
                    NightReviewView(day: nil)
                        .routeDestinations()
                }
            }

            Tab("План", systemImage: "checklist", value: AppTab.plan) {
                NavigationStack(path: $state.planPath) {
                    EveningForecastView()
                        .routeDestinations()
                }
            }

            Tab("Журнал", systemImage: "square.and.pencil", value: AppTab.journal) {
                NavigationStack(path: $state.journalPath) {
                    JournalView()
                        .routeDestinations()
                }
            }

            Tab("Профиль", systemImage: "person.crop.circle", value: AppTab.profile) {
                NavigationStack(path: $state.profilePath) {
                    ProfileView()
                        .routeDestinations()
                }
            }
        }
        .tint(state.activeMode.palette.fg)
        .haptic(.selection, trigger: state.tab)
        .sheet(item: $state.sheet) { route in
            SheetHost(route: route)
        }
        .fullScreenCover(item: $state.cover) { _ in
            WindDownFlow()
        }
    }
}

// MARK: - Routes

extension View {
    func routeDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            RouteView(route: route)
        }
    }
}

struct RouteView: View {
    let route: AppRoute

    var body: some View {
        switch route {
        case .nightReview(let day): NightReviewView(day: day)
        case .factors: FactorsView()
        case .sleepDebt: SleepDebtView()
        case .environment: EnvironmentView()
        case .circadian: CircadianView()
        case .healthSignals: HealthSignalsView()
        case .eveningPlan: EveningPlanView()
        case .insights: InsightsView()
        case .experimentSetup: ExperimentSetupView()
        case .experimentProgress: ExperimentProgressView()
        case .experimentResults(let id): ExperimentResultsView(experimentID: id)
        case .dataSources: DataSourcesView()
        }
    }
}

struct SheetHost: View {
    let route: SheetRoute

    var body: some View {
        switch route {
        case .checkIn: CheckInSheet()
        case .whyPlan: WhyPlanSheet()
        case .customFactor: CustomFactorSheet()
        case .profileAnswers: ProfileAnswersSheet()
        case .sleepGoal: SleepGoalSheet()
        case .alarm: SmartAlarmView(closesNight: false)
        }
    }
}
