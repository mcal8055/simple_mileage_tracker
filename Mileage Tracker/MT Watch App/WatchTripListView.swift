//
//  WatchTripListView.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/16/25.
//


import SwiftUI
import CoreLocation

struct WatchTripListView: View {
    @EnvironmentObject private var store: MileageStore
    @StateObject private var locationManager = LocationManager()

    // In-progress end flow (no odometer on watch for simplicity)
    @State private var isEnding = false

    var body: some View {
        List {
            if let inProgress = store.currentTripInProgress {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("In Progress")
                            .font(.headline)

                        Text(shortDateTime(inProgress.date))
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        if let slat = inProgress.startLat, let slon = inProgress.startLon {
                            Text("Start: \(formatCoord(slat)),\(formatCoord(slon))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 8) {
                            Button("End") {
                                Task {
                                    locationManager.requestWhenInUseAuthorization()
                                    _ = await locationManager.captureOneShotLocation()
                                    await finalizeTrip()
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)

                            Button("Cancel", role: .destructive) {
                                store.cancelCurrentTrip()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }

                        statusView
                    }
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Button("Start Trip") {
                            Task {
                                locationManager.requestWhenInUseAuthorization()
                                let loc = await locationManager.captureOneShotLocation()
                                let lat = loc?.coordinate.latitude
                                let lon = loc?.coordinate.longitude
                                store.startTrip(at: Date(), startLat: lat, startLon: lon)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)

                        statusView
                    }
                }
            }

            Section("Trips") {
                ForEach(store.trips) { trip in
                    WatchTripRow(trip: trip)
                }
                .onDelete(perform: store.delete)
            }
        }
        .navigationTitle("Mileage")
    }

    // MARK: - Helpers

    private func finalizeTrip() async {
        var endLat: Double?
        var endLon: Double?
        if case .gotFix(let loc) = locationManager.status {
            endLat = loc.coordinate.latitude
            endLon = loc.coordinate.longitude
        }
        // On watch we omit odometer entry; pass 0.
        store.finalizeCurrentTrip(endOdo: 0, endLat: endLat, endLon: endLon)
    }

    @ViewBuilder
    private var statusView: some View {
        switch locationManager.status {
        case .idle:
            EmptyView()
        case .requesting:
            HStack(spacing: 6) {
                ProgressView()
                Text("Locating…")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        case .authorized:
            Text("Location OK")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .denied:
            Text("Location denied")
                .font(.caption2)
                .foregroundStyle(.red)
        case .failed(let msg):
            Text("Failed: \(msg)")
                .font(.caption2)
                .foregroundStyle(.red)
        case .gotFix(let loc):
            Text("\(formatCoord(loc.coordinate.latitude)),\(formatCoord(loc.coordinate.longitude))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func shortDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func formatCoord(_ v: Double) -> String {
        String(format: "%.4f", v)
    }
}
