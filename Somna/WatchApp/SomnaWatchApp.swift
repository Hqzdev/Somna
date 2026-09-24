import SwiftUI

@main
struct SomnaWatchApp: App {
    @StateObject private var connection = WatchConnection()

    var body: some Scene {
        WindowGroup {
            WatchRootView(connection: connection)
                .task { connection.start() }
        }
    }
}
