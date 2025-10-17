//
//  MileageStore.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import Foundation
import Combine
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class MileageStore: ObservableObject {
    @Published var trips: [Trip] = [] {
        didSet { Task { await saveTrips() } }
    }

    // In-progress trip (not yet finalized)
    @Published var currentTripInProgress: Trip? {
        didSet { Task { await saveInProgress() } }
    }

    private let tripsFileName = "trips.json"
    private let inProgressFileName = "trip_in_progress.json"
    private let pointsDirectoryName = "points"

    // Injected base directory for persistence (defaults to app Documents).
    private let baseDirectoryURL: URL

    // Foreground-only breadcrumb recorder
    private let recorder = LocationRecordingController()

    // MARK: - Init

    // Designated initializer with injectable base directory for tests.
    init(baseDirectoryURL: URL? = nil) {
        if let baseDirectoryURL {
            self.baseDirectoryURL = baseDirectoryURL
        } else {
            // Default to Documents for app usage.
            self.baseDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        }

        Task {
            await loadTrips()
            await loadInProgress()
        }
    }

    // MARK: - Start / End flow

    func startTrip(at date: Date = Date(), startLat: Double?, startLon: Double?) {
        var t = Trip(
            date: date,
            startOdo: 0, // unknown at start; user can fill later if desired
            endOdo: 0,
            purpose: "",
            category: "",
            notes: "",
            createdAt: Date(),
            startLat: startLat,
            startLon: startLon,
            endLat: nil,
            endLon: nil,
            routeMiles: nil,
            recordedMiles: nil,
            pointsFileName: nil,
            pointsCount: nil
        )
        currentTripInProgress = t

        // Ensure directories and start recorder (foreground-only)
        do {
            try ensureBaseDirectoryExists()
            try ensurePointsDirectoryExists()
            try recorder.start(for: t.id, baseDirectory: baseDirectoryURL)
            setIdleTimerDisabled(true)
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func finalizeCurrentTrip(endOdo: Double, endLat: Double?, endLon: Double?) {
        guard var t = currentTripInProgress else { return }
        t.endOdo = endOdo
        t.endLat = endLat
        t.endLon = endLon
        t.endDate = Date() // capture end timestamp

        // Stop recorder and attach summary
        let summary = recorder.stop(cancel: false)
        setIdleTimerDisabled(false)
        t.recordedMiles = summary.recordedMiles > 0 ? summary.recordedMiles : nil
        t.pointsFileName = summary.fileName
        t.pointsCount = summary.pointsCount > 0 ? summary.pointsCount : nil

        // Save immediately
        trips.append(t)
        sortInMemory()
        currentTripInProgress = nil

        // If we have both coordinates, compute route miles asynchronously and update later.
        if let sLat = t.startLat, let sLon = t.startLon,
           let eLat = t.endLat, let eLon = t.endLon {
            let start = CLLocationCoordinate2D(latitude: sLat, longitude: sLon)
            let end = CLLocationCoordinate2D(latitude: eLat, longitude: eLon)

            Task.detached(priority: .utility) { [weak self] in
                let miles = await RouteDistanceCalculator.routeMiles(from: start, to: end)
                guard let miles, miles > 0 else { return }
                await self?.applyRouteMiles(miles, toTripID: t.id)
            }
        }
    }

    private func applyRouteMiles(_ miles: Double, toTripID id: UUID) {
        guard let idx = trips.firstIndex(where: { $0.id == id }) else { return }
        var updated = trips[idx]
        updated.routeMiles = miles
        trips[idx] = updated
        // trips didSet will persist
    }

    func cancelCurrentTrip() {
        // Stop recorder and delete partial file
        _ = recorder.stop(cancel: true)
        setIdleTimerDisabled(false)
        currentTripInProgress = nil
    }

    // MARK: - Live in-progress stats

    func liveRecordedMiles() -> Double {
        recorder.currentRecordedMiles
    }

    func livePointsCount() -> Int {
        recorder.currentPointsCount
    }

    // MARK: - CRUD (legacy edit path still supported)

    func add(_ trip: Trip) {
        trips.append(trip)
        sortInMemory()
    }

    func update(_ trip: Trip) {
        if let idx = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[idx] = trip
            sortInMemory()
        }
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            if trips.indices.contains(index) {
                trips.remove(at: index)
            }
        }
    }

    func replaceAll(_ newTrips: [Trip]) {
        trips = newTrips
        sortInMemory()
    }

    private func sortInMemory() {
        trips.sort { $0.date < $1.date }
    }

    // MARK: - Persistence

    private var tripsURL: URL {
        baseDirectoryURL.appendingPathComponent(tripsFileName)
    }

    private var inProgressURL: URL {
        baseDirectoryURL.appendingPathComponent(inProgressFileName)
    }

    private var pointsDirectoryURL: URL {
        baseDirectoryURL.appendingPathComponent(pointsDirectoryName, isDirectory: true)
    }

    // Build a full URL to a points file name under the points directory.
    func pointsFileURL(fileName: String?) -> URL? {
        guard let name = fileName, !name.isEmpty else { return nil }
        return pointsDirectoryURL.appendingPathComponent(name)
    }

    private func encoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return enc
    }

    private func decoder() -> JSONDecoder {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }

    func loadTrips() async {
        do {
            guard FileManager.default.fileExists(atPath: tripsURL.path) else { return }
            let data = try Data(contentsOf: tripsURL)
            let loaded = try decoder().decode([Trip].self, from: data)
            self.trips = loaded.sorted { $0.date < $1.date }
        } catch {
            print("Failed to load trips: \(error)")
        }
    }

    func saveTrips() async {
        do {
            let data = try encoder().encode(trips)
            try ensureBaseDirectoryExists()
            try data.write(to: tripsURL, options: [.atomic])
        } catch {
            print("Failed to save trips: \(error)")
        }
    }

    func loadInProgress() async {
        do {
            guard FileManager.default.fileExists(atPath: inProgressURL.path) else { return }
            let data = try Data(contentsOf: inProgressURL)
            let loaded = try decoder().decode(Trip.self, from: data)
            self.currentTripInProgress = loaded
        } catch {
            print("Failed to load in-progress trip: \(error)")
        }
    }

    func saveInProgress() async {
        do {
            try ensureBaseDirectoryExists()
            if let t = currentTripInProgress {
                let data = try encoder().encode(t)
                try data.write(to: inProgressURL, options: [.atomic])
            } else {
                // Remove file if exists
                if FileManager.default.fileExists(atPath: inProgressURL.path) {
                    try FileManager.default.removeItem(at: inProgressURL)
                }
            }
        } catch {
            print("Failed to save in-progress trip: \(error)")
        }
    }

    private func ensureBaseDirectoryExists() throws {
        try FileManager.default.createDirectory(at: baseDirectoryURL, withIntermediateDirectories: true)
    }

    private func ensurePointsDirectoryExists() throws {
        try FileManager.default.createDirectory(at: pointsDirectoryURL, withIntermediateDirectories: true)
    }

    // MARK: - Idle timer control (iOS/iPadOS only)

    private func setIdleTimerDisabled(_ disabled: Bool) {
        #if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = disabled
        #else
        // No-op on platforms without UIKit
        _ = disabled
        #endif
    }
}

