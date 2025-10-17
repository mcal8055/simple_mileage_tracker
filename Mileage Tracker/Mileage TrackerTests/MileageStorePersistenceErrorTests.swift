//
//  MileageStorePersistenceErrorTests.swift
//  Mileage TrackerTests
//
//  Created by Josh McAlister on 10/16/25.
//

import Testing
@testable import Mileage_Tracker
internal import Foundation

@Suite("MileageStore - persistence error handling")
struct MileageStorePersistenceErrorTests {

    // Helper to make a unique temp directory URL for each test
    private func uniqueTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - Corrupted JSON handling

    @Test("loadTrips ignores corrupted trips.json and does not crash")
    func loadTripsCorruptedJSON() async throws {
        let base = uniqueTempDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Write invalid data to trips.json
        let tripsURL = base.appendingPathComponent("trips.json")
        try Data("not valid json".utf8).write(to: tripsURL, options: .atomic)

        // Initialize store pointing to same directory
        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Give async load a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        // Expect safe state (empty trips) and no crash
        let count = await MainActor.run { store.trips.count }
        #expect(count == 0)
    }

    @Test("loadInProgress ignores corrupted trip_in_progress.json and does not crash")
    func loadInProgressCorruptedJSON() async throws {
        let base = uniqueTempDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Write invalid data to trip_in_progress.json
        let inProgressURL = base.appendingPathComponent("trip_in_progress.json")
        try Data("{ this is: not json }".utf8).write(to: inProgressURL, options: .atomic)

        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Give async load a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        let inProgressIsNil = await MainActor.run { store.currentTripInProgress == nil }
        #expect(inProgressIsNil)
    }

    // MARK: - Schema mismatch handling

    @Test("loadTrips handles schema mismatch (wrong types / missing fields)")
    func loadTripsSchemaMismatch() async throws {
        let base = uniqueTempDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Write structurally valid JSON but wrong schema for Trip array
        // e.g., strings where numbers expected
        let badTrips = """
        [
            {
                "id":"\(UUID().uuidString)",
                "date":"1970-01-01T00:00:00Z",
                "startOdo":"zero",
                "endOdo":"ten",
                "purpose": 123,
                "category": true,
                "notes": [],
                "createdAt":"1970-01-01T00:00:00Z"
            }
        ]
        """
        try Data(badTrips.utf8).write(to: base.appendingPathComponent("trips.json"), options: .atomic)

        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Give async load a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        let count = await MainActor.run { store.trips.count }
        #expect(count == 0)
    }

    @Test("loadInProgress handles schema mismatch (wrong types / missing fields)")
    func loadInProgressSchemaMismatch() async throws {
        let base = uniqueTempDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // Write structurally valid JSON but wrong schema for single Trip
        let badTrip = """
        {
            "id":"\(UUID().uuidString)",
            "date":"not-a-date",
            "startOdo":"x",
            "endOdo":{},
            "purpose": null
        }
        """
        try Data(badTrip.utf8).write(to: base.appendingPathComponent("trip_in_progress.json"), options: .atomic)

        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Give async load a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        let inProgressIsNil = await MainActor.run { store.currentTripInProgress == nil }
        #expect(inProgressIsNil)
    }

    // MARK: - Unwritable base directory scenarios

    @Test("saveTrips handles directory creation failure without crashing")
    func saveTripsDirectoryCreationFailure() async throws {
        let base = uniqueTempDirectory()

        // Create a FILE at the path where a directory is expected.
        // This causes createDirectory(at:) to fail with "File exists" (ENOTDIR) when called.
        try Data("blocker".utf8).write(to: base, options: .atomic)

        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Trigger a save by mutating trips
        await MainActor.run {
            store.replaceAll([
                Trip(date: Date(), startOdo: 0, endOdo: 1, purpose: "A", category: "", notes: "")
            ])
        }

        // Give async save a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        // We can't assert on file system (since creation failed by design), but we can assert no crash and trips remain in memory.
        let purposes = await MainActor.run { store.trips.map { $0.purpose } }
        #expect(purposes == ["A"])
    }

    @Test("saveInProgress handles directory creation failure without crashing")
    func saveInProgressDirectoryCreationFailure() async throws {
        let base = uniqueTempDirectory()

        // Block directory creation the same way
        try Data("blocker".utf8).write(to: base, options: .atomic)

        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Set an in-progress trip to trigger save
        await MainActor.run {
            store.startTrip(at: Date(), startLat: nil, startLon: nil)
        }

        // Give async save a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        // Assert app is still alive and state is present in memory
        let hasInProgress = await MainActor.run { store.currentTripInProgress != nil }
        #expect(hasInProgress)
    }

    // MARK: - Ensure base directory created on first successful save

    @Test("ensureBaseDirectoryExists creates directory on first save")
    func ensureDirectoryCreatedOnSave() async throws {
        let base = uniqueTempDirectory()
        // Do not create the directory; let the store create it on save.

        let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

        // Trigger a save
        await MainActor.run {
            store.replaceAll([
                Trip(date: Date(), startOdo: 0, endOdo: 1, purpose: "B", category: "", notes: "")
            ])
        }

        // Give async save a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: base.path, isDirectory: &isDir)
        #expect(exists && isDir.boolValue)
    }
}
