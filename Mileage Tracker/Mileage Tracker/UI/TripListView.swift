//
//  TripListView.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import SwiftUI
import CoreLocation

struct TripListView: View {
    @EnvironmentObject private var store: MileageStore
    @StateObject private var locationManager = LocationManager()

    @State private var showingEdit = false
    @State private var editTrip: Trip?

    @State private var shareItem: ShareItem?

    // End trip sheet
    @State private var showingEndSheet = false
    @State private var endOdoText: String = ""

    // Live in-progress stats
    @State private var liveMiles: Double = 0
    @State private var livePoints: Int = 0
    @State private var isPollingStats: Bool = false
    @State private var statsTimer: Timer?

    var body: some View {
        NavigationStack {
            List {
                // In-progress banner / controls
                if let inProgress = store.currentTripInProgress {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trip in Progress")
                                .font(.headline)

                            Text("Started: \(dateTimeString(inProgress.date))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let slat = inProgress.startLat, let slon = inProgress.startLon {
                                Text("Start: \(formatCoord(slat)), \(formatCoord(slon))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }

                            // Live recorded stats line
                            HStack {
                                Text("Recorded:")
                                Spacer()
                                Text("\(milesString(liveMiles)) (\(livePoints) pts)")
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                            .font(.footnote)

                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    Task {
                                        // Capture end location first
                                        locationManager.requestWhenInUseAuthorization()
                                        _ = await locationManager.captureOneShotLocation()
                                        // Present end odometer prompt (optional)
                                        endOdoText = ""
                                        showingEndSheet = true
                                    }
                                } label: {
                                    Label("End Trip", systemImage: "flag.checkered")
                                        .font(.body)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(role: .destructive) {
                                    store.cancelCurrentTrip()
                                } label: {
                                    Label("Cancel", systemImage: "xmark.circle")
                                        .font(.body)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // Status for location manager
                            statusView
                        }
                        .padding(.vertical, 4)
                        .onAppear { startPollingStats() }
                        .onDisappear { stopPollingStats() }
                    }
                } else {
                    // Start trip control when no trip is in progress
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .center, spacing: 12) {
                                Button {
                                    Task {
                                        locationManager.requestWhenInUseAuthorization()
                                        let loc = await locationManager.captureOneShotLocation()
                                        let lat = loc?.coordinate.latitude
                                        let lon = loc?.coordinate.longitude
                                        store.startTrip(at: Date(), startLat: lat, startLon: lon)
                                        // Reset live stats when starting
                                        liveMiles = 0
                                        livePoints = 0
                                        startPollingStats()
                                    }
                                } label: {
                                    Label("Start Trip", systemImage: "play.circle.fill")
                                        .font(.body)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            statusView
                        }
                        .padding(.vertical, 4)
                        .onAppear { stopPollingStats() } // no in-progress trip
                    }
                }

                // Existing trips
                Section("Trips") {
                    ForEach(store.trips) { trip in
                        Button {
                            // Present edit for this specific trip
                            editTrip = trip
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(dateString(trip.date))
                                        .font(.headline)
                                    if !trip.purpose.isEmpty {
                                        Text(trip.purpose)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                // Prefer automated miles via exportMiles (recorded > route > odometer)
                                Text(milesString(trip.exportMiles))
                                    .monospacedDigit()
                                    .foregroundStyle(.primary)
                            }
                        }
                        // Context menu: per-trip breadcrumbs file removed in master-only mode.
                        .contextMenu {
                            if let url = store.pointsMasterFileURL() {
                                Button {
                                    shareItem = ShareItem(url: url)
                                } label: {
                                    Label("Export All Breadcrumbs (.jsonl)", systemImage: "square.and.arrow.up")
                                }
                            } else {
                                Text("No breadcrumbs file")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if let url = store.pointsMasterFileURL() {
                                Button {
                                    shareItem = ShareItem(url: url)
                                } label: {
                                    Label("Export", systemImage: "square.and.arrow.up")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                    .onDelete(perform: store.delete)
                }
            }
            .navigationTitle("Trips")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Export All") { exportAllCSV() }
                        Button("Export Week") { exportCurrentWeekCSV() }
                        Button("Export JSON") { exportAllBreadcrumbsJSON() } // Now uses master file when available
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    EditButton() // Enables bulk delete via edit mode
                    Button {
                        // Present new trip editor
                        editTrip = nil
                        showingEdit = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Trip")
                }
            }
            // Sheet for editing existing trips (bound to selected Trip)
            .sheet(item: $editTrip) { trip in
                EditTripView(trip: trip)
            }
            // Sheet for adding a new trip
            .sheet(isPresented: $showingEdit) {
                EditTripView(trip: nil)
            }
            // Share sheets
            .sheet(item: $shareItem) { item in
                ShareSheet(activityItems: [item.url])
            }
            // Finalize sheet
            .sheet(isPresented: $showingEndSheet) {
                endTripSheet
                    .presentationDetents([.height(220)])
            }
            .onChange(of: store.currentTripInProgress != nil) { _, active in
                // Start/stop polling based on trip state
                if active {
                    startPollingStats()
                } else {
                    stopPollingStats()
                }
            }
        }
    }

    // MARK: - Polling live stats

    @MainActor
    private func startPollingStats() {
        guard !isPollingStats else { return }
        isPollingStats = true

        // Ensure previous timer is cleared
        statsTimer?.invalidate()
        statsTimer = nil

        // Use selector-based timer with a proxy that executes a closure on fire.
        let proxy = TimerProxy { [weak store] in
            // If trip ended, stop polling
            if store?.currentTripInProgress == nil {
                stopPollingStats()
                return
            }
            liveMiles = store?.liveRecordedMiles() ?? 0
            livePoints = store?.livePointsCount() ?? 0
        }

        let timer = Timer.scheduledTimer(timeInterval: 1.0, target: proxy, selector: #selector(TimerProxy.fire), userInfo: nil, repeats: true)
        // Retain the proxy via the timer; no additional strong refs needed.
        RunLoop.main.add(timer, forMode: .common)
        statsTimer = timer
    }

    @MainActor
    private func stopPollingStats() {
        statsTimer?.invalidate()
        statsTimer = nil
        isPollingStats = false
    }

    // Helper proxy object so the Timer calls back into a closure on main actor.
    private final class TimerProxy: NSObject {
        private let onFire: @MainActor () -> Void

        init(onFire: @escaping @MainActor () -> Void) {
            self.onFire = onFire
        }

        @objc func fire() {
            Task { @MainActor in
                onFire()
            }
        }
    }

    // MARK: - Location status UI

    @ViewBuilder
    private var statusView: some View {
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

    // MARK: - End Trip sheet

    @ViewBuilder
    private var endTripSheet: some View {
        NavigationStack {
            Form {
                Section("End Odometer (Optional)") {
                    TextField("End odometer", text: $endOdoText)
                        .keyboardType(.decimalPad)
                    Text("You can leave this blank; distance will be computed from your recorded route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Finalize Trip")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingEndSheet = false }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { finalizeTrip() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private func finalizeTrip() {
        let endOdo = Double(endOdoText) ?? 0
        // Capture end coordinates if we have a recent fix
        var endLat: Double?
        var endLon: Double?
        if case .gotFix(let loc) = locationManager.status {
            endLat = loc.coordinate.latitude
            endLon = loc.coordinate.longitude
        }
        store.finalizeCurrentTrip(endOdo: endOdo, endLat: endLat, endLon: endLon)
        showingEndSheet = false
    }

    // MARK: - Export All

    private func exportAllCSV() {
        let csv = CSVExporter.makeCSV(trips: store.trips)
        share(csvString: csv, suggestedName: "trips_all_\(timestamp()).csv")
    }

    // MARK: - Export Current Week

    private func exportCurrentWeekCSV() {
        let today = Date()
        guard let range = isoWeekRange(containing: today) else { return }
        let weekTrips = store.trips
            .filter { range.contains($0.date) }
            .sorted { $0.date < $1.date }

        let csv = CSVExporter.makeCSV(trips: weekTrips)
        let (year, week) = isoYearWeek(for: today)
        share(csvString: csv, suggestedName: "trips_\(year)-W\(String(format: "%02d", week)).csv")
    }

    // MARK: - Export JSON (breadcrumbs)

    private func exportAllBreadcrumbsJSON() {
        // Prefer master file when available (audit-friendly single source).
        if let master = store.pointsMasterFileURL() {
            shareItem = ShareItem(url: master)
            return
        }

        // Fallback: combine any per-trip files (legacy).
        let urls: [URL] = store.trips
            .compactMap { store.pointsFileURL(fileName: $0.pointsFileName) }
            .reduce(into: [], { acc, url in
                if !acc.contains(url) { acc.append(url) }
            })

        guard !urls.isEmpty else {
            return
        }

        do {
            let combinedURL = try writeCombinedJSONL(from: urls, name: "points_all_\(timestamp()).jsonl")
            shareItem = ShareItem(url: combinedURL)
        } catch {
            print("Failed to build combined JSONL: \(error)")
        }
    }

    private func writeCombinedJSONL(from urls: [URL], name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let outURL = dir.appendingPathComponent(name)

        // Create/overwrite the output file
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }
        FileManager.default.createFile(atPath: outURL.path, contents: nil)

        let outHandle = try FileHandle(forWritingTo: outURL)
        defer { try? outHandle.close() }

        // Optional comment header line
        if let headerData = "# Combined TripPoint JSON Lines (concatenated)\n".data(using: .utf8) {
            outHandle.write(headerData)
        }

        // Append each source file verbatim
        for url in urls {
            // Stream copy to avoid large memory spikes
            let inHandle = try FileHandle(forReadingFrom: url)
            defer { try? inHandle.close() }

            while let chunk = try inHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                outHandle.write(chunk)
            }
            // Ensure final newline between files (JSONL typically ends with newline; be tolerant)
            if let nl = "\n".data(using: .utf8) {
                outHandle.write(nl)
            }
        }

        return outURL
    }

    // MARK: - Sharing helpers

    private func share(csvString: String, suggestedName: String) {
        do {
            let url = try writeTempCSV(csvString, name: suggestedName)
            shareItem = ShareItem(url: url)
        } catch {
            print("Failed to write CSV: \(error)")
        }
    }

    private func writeTempCSV(_ csv: String, name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(name)
        try csv.data(using: .utf8)?.write(to: url, options: .atomic)
        return url
    }

    private func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date())
    }

    // MARK: - ISO Week helpers

    private func isoCalendar() -> Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        cal.minimumDaysInFirstWeek = 4
        return cal
    }

    private func isoYearWeek(for date: Date) -> (Int, Int) {
        let cal = isoCalendar()
        let year = cal.component(.yearForWeekOfYear, from: date)
        let week = cal.component(.weekOfYear, from: date)
        return (year, week)
    }

    private func isoWeekRange(containing date: Date) -> Range<Date>? {
        let cal = isoCalendar()
        let dayStart = cal.startOfDay(for: date)
        guard let weekInterval = cal.dateInterval(of: .weekOfYear, for: dayStart) else { return nil }
        return weekInterval.start..<weekInterval.end
    }

    // MARK: - Formatting

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f.string(from: date)
    }

    private func dateTimeString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func milesString(_ miles: Double) -> String {
        String(format: "%.1f mi", miles)
    }

    private func formatCoord(_ v: Double) -> String {
        String(format: "%.5f", v)
    }
}

// MARK: - Share helpers

private struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

