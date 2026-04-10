//
//  MileageApp.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import SwiftUI

@main
struct MileageApp: App {
    @StateObject private var store = MileageStore()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some Scene {
        WindowGroup {
            if hasSeenOnboarding {
                TripListView()
                    .environmentObject(store)
            } else {
                OnboardingView()
            }
        }
    }
}
