//
//  ContentView.swift
//  Somna
//
//  Root: onboarding on first launch, then the five-tab shell.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(SomnaStore.self) private var store

    private var scheme: ColorScheme {
        guard store.isOnboarded else { return .light }
        return state.activeMode.palette.isDark ? .dark : .light
    }

    var body: some View {
        root
            .animation(.easeInOut(duration: 0.3), value: store.isOnboarded)
            .preferredColorScheme(scheme)
            .onOpenURL { url in
                guard store.isOnboarded else { return }
                state.open(widgetLink: url)
            }
            .task(id: quickActionKey) {
                guard store.hasLoaded, store.isOnboarded,
                      let action = QuickActionRouter.shared.pending else { return }
                QuickActionRouter.shared.pending = nil
                state.perform(action)
            }
            .modifier(AppHaptics(onboarded: store.isOnboarded, toast: state.toast, cover: state.cover,
                                 checkInCount: store.checkIns.count))
            .environment(\EnvironmentValues.hapticsEnabled, store.settings.hapticsEnabled)
            .onChange(of: store.isOnboarded) { _, onboarded in
                if !onboarded { state.resetNavigation() }
            }
    }

    /// Changes when a quick action arrives or the data becomes ready for it.
    private var quickActionKey: String {
        "\(QuickActionRouter.shared.pending?.rawValue ?? "-")|\(store.hasLoaded)|\(store.isOnboarded)"
    }

    private var root: some View {
        ZStack(alignment: .top) {
            if !store.hasLoaded {
                Palette.dawn.bg.ignoresSafeArea()
            } else if store.isOnboarded {
                RootTabView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }

            if let toast = state.toast {
                ToastView(text: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
    }
}

/// App-level moments: finished onboarding, saved check-in, toasts and
/// entering bedtime mode. Kept apart so each closure is typed.
private struct AppHaptics: ViewModifier {
    let onboarded: Bool
    let toast: String?
    let cover: CoverRoute?
    let checkInCount: Int

    func body(content: Content) -> some View {
        content
            .haptic(.success, trigger: onboarded) { (_: Bool, done: Bool) -> Bool in
                done
            }
            .haptic(.success, trigger: checkInCount) { (old: Int, new: Int) -> Bool in
                new > old
            }
            .haptic(Haptic.tap, trigger: toast) { (_: String?, toast: String?) -> Bool in
                toast != nil
            }
            .hapticDynamic(trigger: cover) { (_: CoverRoute?, cover: CoverRoute?) -> SensoryFeedback? in
                cover == nil ? nil : SensoryFeedback.start
            }
    }
}

struct ToastView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(SomnaFont.body(14, .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 24)
            .accessibilityAddTraits(.isStaticText)
    }
}
