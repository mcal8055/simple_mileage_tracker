//
//  OnboardingView.swift
//  Mileage Tracker
//

import SwiftUI
import CoreLocation

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @StateObject private var locationManager = LocationManager()

    @State private var currentPage = 0

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Purpose
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "car.side")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("Simple Mileage Tracker")
                    .font(.largeTitle.bold())
                Text("Track your mileage automatically.\nPrivate. On-device. No account needed.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Next") { withAnimation { currentPage = 1 } }
                    .buttonStyle(.bordered)
            }
            .padding(32)
            .tag(0)

            // Page 2: How it works
            VStack(spacing: 24) {
                Spacer()
                VStack(alignment: .leading, spacing: 16) {
                    Label("Start a trip", systemImage: "play.circle.fill")
                        .font(.title3)
                    Label("Drive — we record your route", systemImage: "location.fill")
                        .font(.title3)
                    Label("End the trip — miles are calculated", systemImage: "flag.checkered")
                        .font(.title3)
                }
                .padding()
                Text("All data is stored on your device — no servers, no accounts. Even years of trips use minimal storage. Export anytime as CSV for IRS records.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Next") { withAnimation { currentPage = 2 } }
                    .buttonStyle(.bordered)
            }
            .padding(32)
            .tag(1)

            // Page 3: Location permission
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "location.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)
                Text("Location Access")
                    .font(.title.bold())
                Text("We use your location only while tracking a trip to record your route. Location data never leaves your device.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
                Button {
                    locationManager.requestWhenInUseAuthorization()
                    hasSeenOnboarding = true
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(32)
            .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}
