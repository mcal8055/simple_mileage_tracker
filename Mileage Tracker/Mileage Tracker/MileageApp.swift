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

    var body: some Scene {
        WindowGroup {
            TripListView()
                .environmentObject(store)
        }
    }
}
