//
//  SomnaApp.swift
//  Somna
//
//  Reads Apple Health (read-only), computes everything on this iPhone with
//  SomnaCore and keeps the person's data in SwiftData. No account, no server.
//

import SwiftUI
import SwiftData
import Foundation

@main
struct SomnaApp: App {
    @UIApplicationDelegateAdaptor(SomnaAppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var store: SomnaStore?
    @State private var watchBridge: PhoneWatchBridge?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistrar.registerAll()
        if let container = try? SomnaSchema.makeContainer() {
            let store = SomnaStore(container: container)
            let bridge = PhoneWatchBridge(store: store)
            store.onWatchStateChanged = { [weak bridge, weak store] in
                bridge?.publish()
                if let store {
                    WidgetPublisher.publish(store)
                    QuickActions.update(store: store)
                }
            }
            bridge.start()
            Task {
                await store.start()
                bridge.publish()
                WidgetPublisher.publish(store)
                QuickActions.update(store: store)
            }
            _store = State(initialValue: store)
            _watchBridge = State(initialValue: bridge)
        } else {
            _store = State(initialValue: nil)
            _watchBridge = State(initialValue: nil)
        }
    }

    var body: some Scene {
        WindowGroup {
            if let store {
                ContentView()
                    .environment(appState)
                    .environment(store)
                    .onChange(of: scenePhase) { _, phase in
                        if phase == .active {
                            Task { await store.becameActive() }
                        } else if phase == .background {
                            QuickActions.update(store: store)
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "externaldrive.badge.exclamationmark")
                        .font(.largeTitle)
                    Text("Не удалось открыть данные Somna")
                        .font(.headline)
                    Text("Ваши записи не удалены. Перезапустите приложение. Если проблема повторится, сохраните копию устройства перед переустановкой.")
                        .multilineTextAlignment(.center)
                        .font(.subheadline)
                }
                .padding(24)
            }
        }
    }
}
