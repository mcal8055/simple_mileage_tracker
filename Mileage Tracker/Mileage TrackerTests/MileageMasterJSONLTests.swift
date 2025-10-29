//
//  MileageMasterJSONLTests.swift
//  Mileage TrackerTests
//
//  Created by Tests on 10/29/25.
//

import Testing
@testable import Mileage_Tracker
internal import Foundation
import CoreLocation

@Suite("Master JSONL (points_master.jsonl) - TripPointsReader")
struct MileageMasterJSONLTests {

    // Helper to make a unique temp directory URL for each test
    private func uniqueTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func writeMasterFile(at url: URL, lines: [String], includeHeader: Bool = true, ensureFinalNewline: Bool = true) throws {
        // Ensure parent directory exists
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Overwrite
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        if includeHeader {
            if let header = "# TripPoint JSON Lines (all trips; one JSON object per line)\n".data(using: .utf8) {
                handle.write(header)
            }
        }

        for (idx, line) in lines.enumerated() {
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            // Add newline after each line except possibly the last, depending on ensureFinalNewline
            let isLast = idx == lines.count - 1
            if !isLast || ensureFinalNewline {
                if let nl = "\n".data(using: .utf8) {
                    handle.write(nl)
                }
            }
        }
    }

    @Test("loadPointsFromMaster returns only coordinates for the specified tripId")
    func loadPointsFromMasterFiltersByTripId() async throws {
        let base = uniqueTempDirectory()
        let masterURL = base.appendingPathComponent("points_master.jsonl")

        let targetId = UUID()
        let otherId = UUID()

        // Build three points for target, two for other; interleave to test filtering and ordering
        let lines: [String] = [
            // Other trip
            """
            {"tripId":"\(otherId.uuidString)","ts":"1970-01-01T00:00:00Z","lat":1.0,"lon":2.0,"hAcc":10}
            """,
            // Target trip
            """
            {"tripId":"\(targetId.uuidString)","ts":"1970-01-01T00:01:00Z","lat":3.0,"lon":4.0,"hAcc":8}
            """,
            // Target trip
            """
            {"tripId":"\(targetId.uuidString)","ts":"1970-01-01T00:02:00Z","lat":3.1,"lon":4.1,"hAcc":9}
            """,
            // Other trip
            """
            {"tripId":"\(otherId.uuidString)","ts":"1970-01-01T00:03:00Z","lat":5.0,"lon":6.0,"hAcc":12}
            """,
            // Target trip (last)
            """
            {"tripId":"\(targetId.uuidString)","ts":"1970-01-01T00:04:00Z","lat":3.2,"lon":4.2,"hAcc":7}
            """
        ]

        try writeMasterFile(at: masterURL, lines: lines, includeHeader: true, ensureFinalNewline: true)

        let reader = TripPointsReader()
        let coords = try await reader.loadPointsFromMaster(masterURL, forTripId: targetId)

        // Expect exactly the three target points in the same order they appeared
        #expect(coords.count == 3)
        if coords.count == 3 {
            #expect(abs(coords[0].latitude  - 3.0)  < 0.000001 && abs(coords[0].longitude - 4.0)  < 0.000001)
            #expect(abs(coords[1].latitude  - 3.1)  < 0.000001 && abs(coords[1].longitude - 4.1)  < 0.000001)
            #expect(abs(coords[2].latitude  - 3.2)  < 0.000001 && abs(coords[2].longitude - 4.2)  < 0.000001)
        }
    }

    @Test("loadPointsFromMaster ignores header lines and handles trailing line without newline")
    func loadPointsFromMasterIgnoresHeaderAndTrailingLine() async throws {
        let base = uniqueTempDirectory()
        let masterURL = base.appendingPathComponent("points_master.jsonl")

        let targetId = UUID()
        let otherId = UUID()

        // Provide a file where the last JSON line has no newline terminator.
        let lines: [String] = [
            // Mixed with other trip
            """
            {"tripId":"\(targetId.uuidString)","ts":"1970-01-01T00:10:00Z","lat":10.0,"lon":20.0,"hAcc":5}
            """,
            """
            {"tripId":"\(otherId.uuidString)","ts":"1970-01-01T00:11:00Z","lat":99.0,"lon":-99.0,"hAcc":50}
            """,
            // Target line without newline at EOF will still be parsed
            """
            {"tripId":"\(targetId.uuidString)","ts":"1970-01-01T00:12:00Z","lat":10.5,"lon":20.5,"hAcc":6}
            """
        ]

        try writeMasterFile(at: masterURL, lines: lines, includeHeader: true, ensureFinalNewline: false)

        let reader = TripPointsReader()
        let coords = try await reader.loadPointsFromMaster(masterURL, forTripId: targetId)

        #expect(coords.count == 2)
        if coords.count == 2 {
            #expect(abs(coords[0].latitude  - 10.0) < 0.000001 && abs(coords[0].longitude - 20.0) < 0.000001)
            #expect(abs(coords[1].latitude  - 10.5) < 0.000001 && abs(coords[1].longitude - 20.5) < 0.000001)
        }
    }
}
