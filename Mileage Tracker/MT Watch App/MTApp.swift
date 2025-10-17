import SwiftUI

@main
struct MileageWatchApp: App {
    @StateObject private var store = MileageStore()

    var body: some Scene {
        WindowGroup {
            WatchTripListView()
                .environmentObject(store)
        }
    }
}
