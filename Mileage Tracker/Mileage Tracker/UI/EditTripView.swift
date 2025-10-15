//
//  EditTripView.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import SwiftUI
import CoreLocation

struct EditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MileageStore

    // Location manager for one-shot captures
    @StateObject private var locationManager = LocationManager()

    @State private var id: UUID = UUID()
    @State private var date: Date = Date()
    @State private var startOdo: String = ""
    @State private var endOdo: String = ""
    @State private var purpose: String = ""
    @State private var category: String = ""
    @State private var notes: String = ""
    @State private var createdAt: Date = Date()

    // Local coordinate fields
    @State private var startLat: Double?
    @State private var startLon: Double?
    @State private var endLat: Double?
    @State private var endLon: Double?

    let trip: Trip?

    init(trip: Trip?) {
        self.trip = trip
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])

                // Optional odometer section for auditing
                Section("Odometer (Optional)") {
                    TextField("Start", text: $startOdo)
                        .keyboardType(.decimalPad)
                    TextField("End", text: $endOdo)
                        .keyboardType(.decimalPad)
                    HStack {
                        Text("Entered Miles")
                        Spacer()
                        Text(enteredMilesString)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                // Computed miles (read-only): route or odometer only (no haversine preview).
                Section("Distance") {
                    HStack {
                        Text("Computed")
                        Spacer()
                        Text(distanceDisplay)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    Text("Miles will use MapKit route when available; otherwise odometer if entered.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Details") {
                    TextField("Purpose", text: $purpose)
                    TextField("Category", text: $category)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section("Location (optional)") {
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            Task {
                                locationManager.requestWhenInUseAuthorization()
                                if let loc = await locationManager.captureOneShotLocation() {
                                    startLat = loc.coordinate.latitude
                                    startLon = loc.coordinate.longitude
                                }
                            }
                        } label: {
                            Label("Set Start Location", systemImage: "mappin.and.ellipse")
                        }
                        .buttonStyle(.bordered)

                        if let slat = startLat, let slon = startLon {
                            Text("Start: \(formatCoord(slat)), \(formatCoord(slon))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task {
                                locationManager.requestWhenInUseAuthorization()
                                if let loc = await locationManager.captureOneShotLocation() {
                                    endLat = loc.coordinate.latitude
                                    endLon = loc.coordinate.longitude
                                }
                            }
                        } label: {
                            Label("Set End Location", systemImage: "mappin.circle")
                        }
                        .buttonStyle(.bordered)

                        if let elat = endLat, let elon = endLon {
                            Text("End: \(formatCoord(elat)), \(formatCoord(elon))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }

                        // Lightweight status
                        switch locationManager.status {
                        case .idle:
                            EmptyView()
                        case .requesting:
                            HStack(spacing: 6) {
                                ProgressView()
                                Text("Getting location…")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        case .authorized:
                            Text("Location allowed")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        case .denied:
                            Text("Location denied. Enable in Settings > Privacy > Location Services.")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        case .failed(let msg):
                            Text("Location failed: \(msg)")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        case .gotFix(let loc):
                            Text("Got location: \(formatCoord(loc.coordinate.latitude)), \(formatCoord(loc.coordinate.longitude))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(trip == nil ? "New Trip" : "Edit Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if let t = trip {
                    id = t.id
                    date = t.date
                    startOdo = numberString(t.startOdo)
                    endOdo = numberString(t.endOdo)
                    purpose = t.purpose
                    category = t.category
                    notes = t.notes
                    createdAt = t.createdAt
                    startLat = t.startLat
                    startLon = t.startLon
                    endLat = t.endLat
                    endLon = t.endLon
                } else {
                    id = UUID()
                    date = Date()
                    startOdo = ""
                    endOdo = ""
                    purpose = ""
                    category = ""
                    notes = ""
                    createdAt = Date()
                    startLat = nil
                    startLon = nil
                    endLat = nil
                    endLon = nil
                }
            }
        }
    }

    // Always allow save (odometer optional)
    private var canSave: Bool { true }

    private var enteredMilesString: String {
        guard let s = Double(startOdo), let e = Double(endOdo) else { return "—" }
        return String(format: "%.1f", max(0, e - s))
    }

    // Display logic: prefer route (if editing existing trip that already has it), else odometer, else pending/placeholder.
    private var distanceDisplay: String {
        if let t = trip, let r = t.routeMiles, r > 0 {
            return String(format: "%.1f mi", r)
        }
        if let s = Double(startOdo), let e = Double(endOdo), e >= s {
            return String(format: "%.1f mi (odometer)", e - s)
        }
        // If both coords are set but no route yet, hint that it will compute after save.
        if startLat != nil, startLon != nil, endLat != nil, endLon != nil {
            return "Pending route…"
        }
        return "—"
    }

    private func save() {
        let s = Double(startOdo) ?? 0
        let e = Double(endOdo) ?? 0
        let newTrip = Trip(
            id: id,
            date: date,
            startOdo: s,
            endOdo: e,
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            startLat: startLat,
            startLon: startLon,
            endLat: endLat,
            endLon: endLon
        )

        if trip == nil {
            store.add(newTrip)
        } else {
            store.update(newTrip)
        }
        dismiss()
    }

    private func numberString(_ d: Double) -> String {
        if d.rounded(.towardZero) == d {
            return String(format: "%.0f", d)
        } else {
            return String(format: "%.2f", d)
        }
    }

    private func formatCoord(_ v: Double) -> String {
        String(format: "%.5f", v)
    }
}
