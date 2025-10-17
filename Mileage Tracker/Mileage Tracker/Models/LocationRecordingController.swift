//
//  LocationRecordingController.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/16/25.
//

import Foundation
import CoreLocation

// Foreground-only recorder that samples high-accuracy locations while a trip is active,
// appends JSON Lines to a per-trip file, and maintains a running distance total.
@MainActor
final class LocationRecordingController: NSObject {

    // Public summary returned when stopping a recording
    struct Summary {
        let fileName: String?
        let pointsCount: Int
        let recordedMiles: Double
    }

    private let manager = CLLocationManager()

    // Active session state
    private var activeTripID: UUID?
    private var pointsDirURL: URL?
    private var fileURL: URL?
    private var fileHandle: FileHandle?
    private var jsonEncoder = JSONEncoder()

    // Last accepted point for distance accumulation
    private var lastPoint: TripPoint?
    private var metersAccumulated: Double = 0
    private var pointsCount: Int = 0

    // Filtering thresholds (tunable)
    private let maxHorizontalAccuracyMeters: CLLocationAccuracy = 100 // reject worse than 100m
    private let maxJumpMeters: CLLocationDistance = 500              // reject single-hop jumps > 500m unless accuracy is good

    override init() {
        super.init()
        manager.delegate = self
        // High-accuracy foreground-only recording
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 30 // meters; tune 25–50 for your needs
        // NOTE: Do not set allowsBackgroundLocationUpdates; we are foreground-only by design.
        jsonEncoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Live stats (read-only)

    var currentRecordedMiles: Double {
        metersAccumulated / 1609.344
    }

    var currentPointsCount: Int {
        pointsCount
    }

    // Start recording for a specific trip id. Creates/opens a JSON Lines file under baseDirectory/points.
    func start(for tripID: UUID, baseDirectory: URL) throws {
        guard activeTripID == nil else { return } // already recording

        // Ensure points subdirectory exists
        let pointsDir = baseDirectory.appendingPathComponent("points", isDirectory: true)
        try FileManager.default.createDirectory(at: pointsDir, withIntermediateDirectories: true)

        // Prepare file path: trip_<UUID>.jsonl
        let fileName = "trip_\(tripID.uuidString).jsonl"
        let url = pointsDir.appendingPathComponent(fileName)

        // Create file if missing
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }

        // Open for appending
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()

        // Reset counters
        activeTripID = tripID
        pointsDirURL = pointsDir
        fileURL = url
        fileHandle = handle
        lastPoint = nil
        metersAccumulated = 0
        pointsCount = 0

        // Begin high-frequency updates (foreground only)
        manager.startUpdatingLocation()
    }

    // Stop recording. If cancel == true, delete the partial file.
    func stop(cancel: Bool) -> Summary {
        manager.stopUpdatingLocation()

        let summary = Summary(
            fileName: cancel ? nil : fileURL?.lastPathComponent,
            pointsCount: pointsCount,
            recordedMiles: metersAccumulated / 1609.344
        )

        // Close handle
        try? fileHandle?.close()
        fileHandle = nil

        if cancel, let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }

        // Clear state
        activeTripID = nil
        pointsDirURL = nil
        fileURL = nil
        lastPoint = nil
        metersAccumulated = 0
        pointsCount = 0

        return summary
    }

    // MARK: - Internal helpers

    private func append(point: TripPoint) {
        guard let handle = fileHandle else { return }
        do {
            let data = try jsonEncoder.encode(point)
            handle.write(data)
            handle.write(Data([0x0A])) // newline
            pointsCount += 1
        } catch {
            // If writing fails, we still keep recording in memory to avoid losing distance,
            // but the file may be incomplete. Caller can inspect pointsCount.
            print("TripPoint write failed: \(error)")
        }
    }

    private func shouldAccept(_ loc: CLLocation) -> Bool {
        // Basic quality filter
        guard loc.horizontalAccuracy >= 0, loc.horizontalAccuracy <= maxHorizontalAccuracyMeters else {
            return false
        }
        // Reject very old samples (stale)
        if abs(loc.timestamp.timeIntervalSinceNow) > 60 {
            return false
        }
        // Reject impossible coordinates
        let lat = loc.coordinate.latitude
        let lon = loc.coordinate.longitude
        guard lat >= -90, lat <= 90, lon >= -180, lon <= 180 else {
            return false
        }
        // Outlier rejection: if lastPoint exists, reject huge jumps when accuracy isn't great
        if let last = lastPoint {
            let lastLoc = last.clLocation
            let delta = loc.distance(from: lastLoc)
            if delta > maxJumpMeters && loc.horizontalAccuracy > 20 {
                return false
            }
        }
        return true
    }

    private func process(locations: [CLLocation]) {
        for loc in locations {
            guard shouldAccept(loc) else { continue }
            let point = TripPoint(from: loc)

            // Accumulate distance from last accepted point
            if let last = lastPoint {
                metersAccumulated += point.clLocation.distance(from: last.clLocation)
            }
            lastPoint = point

            // Append to file
            append(point: point)
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationRecordingController: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.process(locations: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Foreground-only; we log and continue. No special handling needed here.
        print("Location recording error: \(error)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // We assume caller has already requested "When In Use".
        // If authorization is denied, we won't receive updates; caller can decide how to react.
        // Keep recorder logic simple here.
    }
}

