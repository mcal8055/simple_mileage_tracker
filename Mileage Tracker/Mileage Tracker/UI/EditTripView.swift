//
//  EditTripView.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import SwiftUI
import CoreLocation
import MapKit
import Combine

@MainActor
final class EditTripViewModel: ObservableObject {
    // Core fields
    @Published var id: UUID = UUID()
    @Published var date: Date = Date()
    @Published var endDate: Date? = nil
    @Published var startOdoText: String = ""
    @Published var endOdoText: String = ""
    @Published var purpose: String = ""   // Will represent "Client"
    @Published var category: String = ""  // Will represent "Service"
    @Published var notes: String = ""
    @Published var createdAt: Date = Date()

    // Coordinates
    @Published var startLat: Double?
    @Published var startLon: Double?
    @Published var endLat: Double?
    @Published var endLon: Double?

    // Persisted context we keep (not shown here, but preserved on save)
    @Published var recordedMiles: Double?
    @Published var routeMiles: Double?
    @Published var pointsCount: Int?
    @Published var pointsFileName: String?

    // Points for map preview
    @Published var pointsCoords: [CLLocationCoordinate2D] = []

    private let pointsReader = TripPointsReader()

    init(trip: Trip?) {
        if let t = trip {
            id = t.id
            date = t.date
            endDate = t.endDate
            startOdoText = numberString(t.startOdo)
            endOdoText = numberString(t.endOdo)
            purpose = t.purpose
            category = t.category
            notes = t.notes
            createdAt = t.createdAt
            startLat = t.startLat
            startLon = t.startLon
            endLat = t.endLat
            endLon = t.endLon

            recordedMiles = t.recordedMiles
            routeMiles = t.routeMiles
            pointsCount = t.pointsCount
            pointsFileName = t.pointsFileName
        } else {
            // Defaults for a new trip
            id = UUID()
            date = Date()
            endDate = nil
            startOdoText = ""
            endOdoText = ""
            purpose = ""
            category = ""
            notes = ""
            createdAt = Date()
            startLat = nil
            startLon = nil
            endLat = nil
            endLon = nil

            recordedMiles = nil
            routeMiles = nil
            pointsCount = nil
            pointsFileName = nil
        }
    }

    // MARK: - Derived values

    var startOdo: Double { Double(startOdoText) ?? 0 }
    var endOdo: Double { Double(endOdoText) ?? 0 }

    var enteredMilesString: String {
        guard let s = Double(startOdoText), let e = Double(endOdoText) else { return "—" }
        return String(format: "%.1f", max(0, e - s))
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let lat = startLat, let lon = startLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var endCoordinate: CLLocationCoordinate2D? {
        guard let lat = endLat, let lon = endLon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func computedRegion() -> MKCoordinateRegion? {
        if pointsCoords.count >= 2 {
            var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
            for c in pointsCoords {
                minLat = min(minLat, c.latitude)
                maxLat = max(maxLat, c.latitude)
                minLon = min(minLon, c.longitude)
                maxLon = max(maxLon, c.longitude)
            }
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2, longitude: (minLon + maxLon)/2)
            let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.2),
                                        longitudeDelta: max(0.01, (maxLon - minLon) * 1.2))
            return MKCoordinateRegion(center: center, span: span)
        }
        return fallbackRegionFromEndpoints()
    }

    private func fallbackRegionFromEndpoints() -> MKCoordinateRegion? {
        switch (startCoordinate, endCoordinate) {
        case let (s?, e?):
            let minLat = min(s.latitude, e.latitude)
            let maxLat = max(s.latitude, e.latitude)
            let minLon = min(s.longitude, e.longitude)
            let maxLon = max(s.longitude, e.longitude)
            let center = CLLocationCoordinate2D(latitude: (minLat + maxLat)/2, longitude: (minLon + maxLon)/2)
            let span = MKCoordinateSpan(latitudeDelta: max(0.01, (maxLat - minLat) * 1.2),
                                        longitudeDelta: max(0.01, (maxLon - minLon) * 1.2))
            return MKCoordinateRegion(center: center, span: span)
        case let (s?, nil):
            return MKCoordinateRegion(center: s, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        case let (nil, e?):
            return MKCoordinateRegion(center: e, span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))
        default:
            return nil
        }
    }

    // MARK: - IO

    func pointsURL(using store: MileageStore) -> URL? {
        store.pointsFileURL(fileName: pointsFileName)
    }

    func loadPointsIfAvailable(using store: MileageStore) async {
        // Prefer legacy per-trip file if present
        if let url = pointsURL(using: store) {
            let coords = (try? await pointsReader.loadPoints(from: url)) ?? []
            pointsCoords = coords
            return
        }

        // Fallback: read from master file and filter by this trip's id
        if let masterURL = store.pointsMasterFileURL() {
            let coords = (try? await pointsReader.loadPointsFromMaster(masterURL, forTripId: id)) ?? []
            pointsCoords = coords
            return
        }

        // Nothing available
        pointsCoords = []
    }

    func makeTrip() -> Trip {
        Trip(
            id: id,
            date: date,
            endDate: endDate,
            startOdo: startOdo,
            endOdo: endOdo,
            purpose: purpose.trimmingCharacters(in: .whitespacesAndNewlines),   // Client
            category: category.trimmingCharacters(in: .whitespacesAndNewlines), // Service
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: createdAt,
            startLat: startLat,
            startLon: startLon,
            endLat: endLat,
            endLon: endLon,
            routeMiles: routeMiles,
            recordedMiles: recordedMiles,
            pointsFileName: pointsFileName,
            pointsCount: pointsCount
        )
    }

    // MARK: - Helpers

    private func numberString(_ d: Double) -> String {
        if d.rounded(.towardZero) == d {
            return String(format: "%.0f", d)
        } else {
            return String(format: "%.2f", d)
        }
    }

    func formatCoord(_ v: Double) -> String {
        String(format: "%.5f", v)
    }
}

struct EditTripView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: MileageStore

    @StateObject private var vm: EditTripViewModel

    private let isNew: Bool

    init(trip: Trip?) {
        _vm = StateObject(wrappedValue: EditTripViewModel(trip: trip))
        self.isNew = (trip == nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TripSection(date: $vm.date, end: vm.endDate)

                    // Odometer (Optional) — commented out for now.
                    /*
                    OdometerSection(
                        startOdo: $vm.startOdoText,
                        endOdo: $vm.endOdoText,
                        enteredMilesString: vm.enteredMilesString
                    )
                    */

                    RoutePreviewSection(
                        region: vm.computedRegion(),
                        pointsCoords: vm.pointsCoords,
                        startCoordinate: vm.startCoordinate,
                        endCoordinate: vm.endCoordinate,
                        startLat: vm.startLat,
                        startLon: vm.startLon,
                        endLat: vm.endLat,
                        endLon: vm.endLon,
                        formatCoord: vm.formatCoord
                    )

                    DetailsSection(service: $vm.category, client: $vm.purpose, notes: $vm.notes)
                        .environmentObject(store)

                    Color.clear.frame(height: 40)
                }
                .padding(.horizontal)
                .padding(.top, 12)
            }
            .navigationTitle(isNew ? "New Trip" : "Edit Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 8) }
            .task {
                await vm.loadPointsIfAvailable(using: store)
            }
            .onChange(of: vm.pointsFileName ?? "") { _, _ in
                Task { await vm.loadPointsIfAvailable(using: store) }
            }
        }
    }

    private func save() {
        let trip = vm.makeTrip()
        if isNew {
            store.add(trip)
        } else {
            store.update(trip)
        }
        dismiss()
    }
}

// MARK: - Small section views

private struct TripSection: View {
    @Binding var date: Date
    let end: Date?

    var body: some View {
        Group {
            Text("Trip")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                // Start date/time picker
                DatePicker("", selection: $date, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
                    .labelsHidden()

                // Time summary
                HStack {
                    Text("From")
                    Spacer()
                    Text(timeString(date))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if let end {
                    HStack {
                        Text("To")
                        Spacer()
                        Text(timeString(end))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(durationString(from: date, to: end))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                } else {
                    HStack {
                        Text("To")
                        Spacer()
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let seconds = max(0, end.timeIntervalSince(start))
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}

// Odometer UI commented out for now. Re-enable by uncommenting this block and the call site above.
/*
private struct OdometerSection: View {
    @Binding var startOdo: String
    @Binding var endOdo: String
    let enteredMilesString: String

    var body: some View {
        Group {
            Text("Odometer (Optional)")
                .font(.headline)

            VStack(spacing: 12) {
                HStack {
                    Text("Start")
                    TextField("Start", text: $startOdo)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("End")
                    TextField("End", text: $endOdo)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                }
                HStack {
                    Text("Entered Miles")
                    Spacer()
                    Text(enteredMilesString)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}
*/

private struct RoutePreviewSection: View {
    let region: MKCoordinateRegion?
    let pointsCoords: [CLLocationCoordinate2D]
    let startCoordinate: CLLocationCoordinate2D?
    let endCoordinate: CLLocationCoordinate2D?

    let startLat: Double?
    let startLon: Double?
    let endLat: Double?
    let endLon: Double?
    let formatCoord: (Double) -> String

    var body: some View {
        Group {
            Text("Route Preview")
                .font(.headline)

            if let region {
                Map(position: .constant(.region(region))) {
                    if pointsCoords.count >= 2 {
                        MapPolyline(coordinates: pointsCoords)
                            .stroke(.blue, lineWidth: 3)
                    }
                    if let s = startCoordinate {
                        Marker("Start", coordinate: s).tint(.green)
                    }
                    if let e = endCoordinate {
                        Marker("End", coordinate: e).tint(.red)
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
            } else {
                Text("No coordinates to preview.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 12)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let slat = startLat, let slon = startLon {
                    Text("Start: \(formatCoord(slat)), \(formatCoord(slon))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let elat = endLat, let elon = endLon {
                    Text("End: \(formatCoord(elat)), \(formatCoord(elon))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct DetailsSection: View {
    @EnvironmentObject private var store: MileageStore

    // category = Service, purpose = Client
    @Binding var service: String
    @Binding var client: String
    @Binding var notes: String

    @State private var showingAddClient = false
    @State private var newClientName: String = ""

    private let serviceOptions: [String] = [
        "House Sitting",
        "Drop-ins",
        "Dog Walking",
        "Meet & Greet"
    ]

    var body: some View {
        Group {
            Text("Details")
                .font(.headline)

            VStack(spacing: 12) {
                // Service dropdown (mapped to Trip.category)
                HStack {
                    Text("Service")
                    Spacer()
                    Picker("Service", selection: $service) {
                        ForEach(serviceOptions, id: \.self) { option in
                            Text(option).tag(option)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Client dropdown (mapped to Trip.purpose) with add-new flow
                HStack(alignment: .center) {
                    Text("Client")
                    Spacer()
                    Picker("Client", selection: $client) {
                        ForEach(store.clients, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    .pickerStyle(.menu)
                }

                HStack {
                    Button {
                        newClientName = ""
                        showingAddClient = true
                    } label: {
                        Label("Add New Client", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Spacer()

                    // Quick remove if selected exists
                    if !client.isEmpty, store.clients.contains(where: { $0.caseInsensitiveCompare(client) == .orderedSame }) {
                        Button(role: .destructive) {
                            store.removeClient(named: client)
                            if let first = store.clients.first {
                                client = first
                            } else {
                                client = ""
                            }
                        } label: {
                            Label("Remove Client", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .sheet(isPresented: $showingAddClient) {
            NavigationStack {
                Form {
                    Section("New Client") {
                        TextField("Client name", text: $newClientName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled(false)
                    }
                }
                .navigationTitle("Add Client")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingAddClient = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let name = newClientName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            store.addClient(name)
                            client = name
                            showingAddClient = false
                        }
                        .disabled(newClientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .presentationDetents([.height(220)])
        }
        .onAppear {
            // If service is empty, don't auto-select; user can choose.
            // If client is empty but we have existing clients, preselect first for convenience.
            if client.isEmpty, let first = store.clients.first {
                client = first
            }
        }
    }
}
