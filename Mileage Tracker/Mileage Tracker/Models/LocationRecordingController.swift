//
//  LocationRecordingController.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/16/25.
//

import Foundation
import CoreLocation

// Foreground-only recorder that samples high-accuracy locations while a trip is active,
// appends JSON Lines to a single master file, and maintains a running distance total.
@MainActor
final class LocationRecordingController: NSObject {

    // Public summary returned when stopping a recording
    struct Summary {
        let fileName: String?    // always nil in master-only mode
        let pointsCount: Int
        let recordedMiles: Double
    }

    private let manager = CLLocationManager()

    // Active session state
    private var activeTripID: UUID?
    private var pointsDirURL: URL?
    private var masterFileURL: URL?
    private var masterFileHandle: FileHandle?
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

    var isRecording: Bool { activeTripID != nil }

    var currentRecordedMiles: Double {
        metersAccumulated / 1609.344
    }

    var currentPointsCount: Int {
        pointsCount
    }

    // Start recording for a specific trip id. Opens/creates a single master JSON Lines file under baseDirectory/points.
    func start(for tripID: UUID, baseDirectory: URL) throws {
        guard activeTripID == nil else { return } // already recording

        // Ensure points subdirectory exists
        let pointsDir = baseDirectory.appendingPathComponent("points", isDirectory: true)
        try FileManager.default.createDirectory(at: pointsDir, withIntermediateDirectories: true)

        // Prepare master file path: points_master.jsonl
        let masterURL = pointsDir.appendingPathComponent("points_master.jsonl")
        if !FileManager.default.fileExists(atPath: masterURL.path) {
            FileManager.default.createFile(atPath: masterURL.path, contents: nil)
            // Optional human-readable header; JSONL parsers expecting pure JSON can skip it.
            if let headerData = "# TripPoint JSON Lines (all trips; one JSON object per line)\n".data(using: .utf8) {
                let tmp = try FileHandle(forWritingTo: masterURL)
                try tmp.seekToEnd()
                tmp.write(headerData)
                try? tmp.close()
            }
        }
        let masterHandle = try FileHandle(forWritingTo: masterURL)
        try masterHandle.seekToEnd()

        // Reset counters
        activeTripID = tripID
        pointsDirURL = pointsDir
        masterFileURL = masterURL
        masterFileHandle = masterHandle
        lastPoint = nil
        metersAccumulated = 0
        pointsCount = 0

        // Begin high-frequency updates (foreground only)
        manager.startUpdatingLocation()
    }

    // Stop recording.
    func stop(cancel: Bool) -> Summary {
        manager.stopUpdatingLocation()

        // Close handle first to flush any buffered data
        try? masterFileHandle?.close()
        masterFileHandle = nil

        let summary = Summary(
            fileName: nil, // master-only mode: no per-trip file
            pointsCount: pointsCount,
            recordedMiles: metersAccumulated / 1609.344
        )

        // Clear state
        activeTripID = nil
        pointsDirURL = nil
        masterFileURL = nil
        lastPoint = nil
        metersAccumulated = 0
        pointsCount = 0

        return summary
    }

    // MARK: - Internal helpers

    // Flat JSON object that includes trip UUID alongside the TripPoint fields for audit grouping.
    private struct EncodedPoint: Encodable {
        let tripId: UUID
        let ts: Date
        let lat: Double
        let lon: Double
        let hAcc: Double
        let speed: Double?
        let course: Double?

        init(tripId: UUID, point: TripPoint) {
            self.tripId = tripId
            self.ts = point.ts
            self.lat = point.lat
            self.lon = point.lon
            self.hAcc = point.hAcc
            self.speed = point.speed
            self.course = point.course
        }
    }

    private func append(point: TripPoint) {
        guard let tripId = activeTripID, let handle = masterFileHandle else { return }
        do {
            let encoded = EncodedPoint(tripId: tripId, point: point)
            let data = try jsonEncoder.encode(encoded)
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

            // Append to master file (one JSON object per line, with tripId)
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
