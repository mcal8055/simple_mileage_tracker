//
//  Mileage_TrackerTests.swift
//  Mileage TrackerTests
//
//  Created by Josh McAlister on 10/15/25.
//

import Testing
@testable import Mileage_Tracker
internal import Foundation

@Suite("Trip model")
struct TripTests {

    @Test("Odometer miles clamp to 0 when end < start")
    func milesClamp() {
        let t = Trip(date: .now, startOdo: 120.0, endOdo: 100.0, purpose: "", category: "", notes: "")
        #expect(t.miles == 0)
    }

    @Test("exportMiles prefers routeMiles over odometer miles")
    func exportPrefersRoute() {
        var t = Trip(date: .now, startOdo: 100.0, endOdo: 120.0, purpose: "", category: "", notes: "")
        #expect(t.exportMiles == 20.0)
        t.routeMiles = 18.4
        #expect(t.exportMiles == 18.4)
    }

    @Test("haversineMiles sanity: NYC to Boston ~190 mi straight-line")
    func haversineSanity() throws {
        var t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        t.startLat = 40.7128; t.startLon = -74.0060   // NYC
        t.endLat = 42.3601;   t.endLon = -71.0589     // Boston
        let miles = try #require(t.haversineMiles)
        #expect(miles > 150 && miles < 220)
    }
}

@Suite("CSVExporter")
struct CSVExporterTests {

    @Test("Includes comment and header")
    func headerAndComment() {
        let csv = CSVExporter.makeCSV(trips: [])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 2)
        #expect(lines.first?.starts(with: "#") == true)
        #expect(lines.dropFirst().first == CSVExporter.header[...])
    }

    @Test("Escapes commas, quotes, and newlines")
    func escaping() {
        let t = Trip(
            date: Date(timeIntervalSince1970: 0),
            startOdo: 0,
            endOdo: 0,
            purpose: #"Hello, "World""#,
            category: "Biz,Dev",
            notes: "Line1\nLine2"
        )
        let csv = CSVExporter.makeCSV(trips: [t])
        // Purpose: quotes doubled, field wrapped
        #expect(csv.contains(#""Hello, ""World"""#))
        // Category: contains comma, wrapped
        #expect(csv.contains(#""Biz,Dev""#))
        // Notes: contains newline, wrapped; build expected string to avoid macro parsing issues
        let expectedNotes = "\"Line1\nLine2\""
        #expect(csv.contains(expectedNotes))
    }

    @Test("Formats numbers and coordinates; indicates miles_source")
    func formattingAndSource() {
        var routeTrip = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        routeTrip.routeMiles = 10.0

        let odoTrip = Trip(date: .now.addingTimeInterval(60), startOdo: 5, endOdo: 9, purpose: "", category: "", notes: "")

        var coordTrip = Trip(date: .now.addingTimeInterval(120), startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        coordTrip.startLat = 37.3317
        coordTrip.startLon = -122.0307

        let csv = CSVExporter.makeCSV(trips: [coordTrip, routeTrip, odoTrip])

        // miles_source
        #expect(csv.contains(",10.00,route,"))
        #expect(csv.contains(",4.00,odometer,"))

        // Coordinates formatted to 5 decimals
        #expect(csv.contains(",37.33170,-122.03070,"))

        // Start/end odometers: zero values should be empty fields
        // Look for ,, around the positions where start/end odos would be when zero.
        #expect(csv.contains(",,")) // at least some empty numeric fields
    }

    @Test("Rows sorted by date ascending")
    func sortedByDate() {
        let d1 = Date(timeIntervalSince1970: 1000)
        let d2 = Date(timeIntervalSince1970: 2000)
        let d3 = Date(timeIntervalSince1970: 1500)

        let t1 = Trip(date: d1, startOdo: 0, endOdo: 0, purpose: "A", category: "", notes: "")
        let t2 = Trip(date: d2, startOdo: 0, endOdo: 0, purpose: "B", category: "", notes: "")
        let t3 = Trip(date: d3, startOdo: 0, endOdo: 0, purpose: "C", category: "", notes: "")

        let csv = CSVExporter.makeCSV(trips: [t2, t3, t1])
        let lines = csv.split(separator: "\n").dropFirst(2) // skip comment + header

        // With destination added before purpose, purpose is now the 12th field (0-based index 11)
        let purposes = lines.compactMap { line -> String? in
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 12 else { return nil }
            return String(parts[11]).replacingOccurrences(of: "\"", with: "")
        }
        #expect(purposes == ["A", "C", "B"])
    }
}

@Suite("MileageStore - in memory")
struct MileageStoreInMemoryTests {

    // Helper to make a unique temp directory URL for each test
    private func uniqueTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @Test("add sorts by date ascending")
    func addSorts() async {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        let older = Trip(date: Date(timeIntervalSince1970: 0), startOdo: 120.0, endOdo: 100.0, purpose: "old", category: "", notes: "")
        let newer = Trip(date: Date(), startOdo: 0, endOdo: 0, purpose: "new", category: "", notes: "")

        await MainActor.run {
            store.add(newer)
            store.add(older)
        }
        let firstPurpose = await MainActor.run { store.trips.first?.purpose }
        #expect(firstPurpose == "old")
    }

    @Test("update replaces matching trip by id")
    @MainActor
    func updateReplaces() async {
        let temp = uniqueTempDirectory()
        let store = MileageStore(baseDirectoryURL: temp)
        var t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "A", category: "", notes: "")
        store.add(t)
        t.purpose = "B"
        store.update(t)
        let updatedPurpose = store.trips.first?.purpose
        #expect(updatedPurpose == "B")
    }

    @Test("delete removes at index")
    func deleteRemoves() async {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        let t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "A", category: "", notes: "")
        await MainActor.run { store.add(t) }
        await MainActor.run { store.delete(at: IndexSet(integer: 0)) }
        let isEmpty = await MainActor.run { store.trips.isEmpty }
        #expect(isEmpty)
    }

    @Test("replaceAll swaps and sorts")
    func replaceAllSorts() async {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        let t1 = Trip(date: Date(timeIntervalSince1970: 2000), startOdo: 0, endOdo: 0, purpose: "B", category: "", notes: "")
        let t2 = Trip(date: Date(timeIntervalSince1970: 1000), startOdo: 0, endOdo: 0, purpose: "A", category: "", notes: "")
        await MainActor.run { store.replaceAll([t1, t2]) }
        let purposes = await MainActor.run { store.trips.map { $0.purpose } }
        #expect(purposes == ["A", "B"])
    }

    @Test("startTrip sets currentTripInProgress")
    func startTripSetsInProgress() async {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        await MainActor.run { store.startTrip(at: Date(), startLat: nil, startLon: nil) }
        let hasInProgress = await MainActor.run { store.currentTripInProgress != nil }
        #expect(hasInProgress)
    }

    @Test("cancelCurrentTrip clears in-progress")
    func cancelClearsInProgress() async {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        await MainActor.run {
            store.startTrip(at: Date(), startLat: nil, startLon: nil)
            store.cancelCurrentTrip()
        }
        let hasInProgress = await MainActor.run { store.currentTripInProgress != nil }
        #expect(!hasInProgress)
    }

    @Test("finalize moves in-progress to trips and clears in-progress")
    func finalizeMovesTrip() async throws {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        await MainActor.run {
            store.startTrip(at: Date(), startLat: nil, startLon: nil)
            store.finalizeCurrentTrip(endOdo: 123, endLat: nil, endLon: nil)
        }
        let state = await MainActor.run { (store.currentTripInProgress, store.trips.count) }
        #expect(state.0 == nil)
        #expect(state.1 == 1)
    }

    // MARK: - Persistence round-trips

    @Test("saveTrips then loadTrips round-trips the data")
    func tripsPersistenceRoundTrip() async throws {
        let temp = uniqueTempDirectory()
        // First store writes trips
        let writer = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        let t1 = Trip(date: Date(timeIntervalSince1970: 1000), startOdo: 1, endOdo: 2, purpose: "One", category: "", notes: "")
        let t2 = Trip(date: Date(timeIntervalSince1970: 2000), startOdo: 3, endOdo: 5, purpose: "Two", category: "", notes: "")
        await MainActor.run {
            writer.replaceAll([t2, t1]) // out of order on purpose
        }
        // Give async save a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        // Second store reads trips from same directory
        let reader = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        // Give async load a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        let purposes = await MainActor.run { reader.trips.map { $0.purpose } }
        #expect(purposes == ["One", "Two"]) // sorted by date ascending
    }

    @Test("saveInProgress then loadInProgress round-trips the in-progress trip")
    func inProgressPersistenceRoundTrip() async throws {
        let temp = uniqueTempDirectory()
        let writer = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        await MainActor.run {
            writer.startTrip(at: Date(timeIntervalSince1970: 1234), startLat: 1.23, startLon: 4.56)
        }
        // Give async save a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        let reader = await MainActor.run { MileageStore(baseDirectoryURL: temp) }
        // Give async load a tick
        try await Task.sleep(nanoseconds: 100_000_000)

        // Read isolated properties on the MainActor and return plain values
        let (date, lat, lon) = await MainActor.run { () -> (TimeInterval?, Double?, Double?) in
            let inProgress = reader.currentTripInProgress
            return (inProgress?.date.timeIntervalSince1970,
                    inProgress?.startLat,
                    inProgress?.startLon)
        }

        let dateMatches = date == 1234
        let latMatches = lat == 1.23
        let lonMatches = lon == 4.56
        #expect(dateMatches && latMatches && lonMatches)
    }

    // MARK: - Route miles application

    @Test("applyRouteMiles updates the correct trip by id")
    func applyRouteMilesUpdatesTrip() async throws {
        let temp = uniqueTempDirectory()
        let store = await MainActor.run { MileageStore(baseDirectoryURL: temp) }

        // Create a trip with coordinates set up-front to avoid mutating a captured var inside @Sendable closures.
        let t = Trip(
            date: Date(timeIntervalSince1970: 1000),
            startOdo: 0,
            endOdo: 0,
            purpose: "Routed",
            category: "",
            notes: "",
            createdAt: Date(),
            startLat: 37.0,
            startLon: -122.0,
            endLat: nil,
            endLon: nil,
            routeMiles: nil
        )

        await MainActor.run {
            store.add(t)
        }

        // Simulate background route computation by updating the trip by id.
        await MainActor.run {
            var updated = t
            updated.routeMiles = 12.34
            store.update(updated)
        }

        let miles = await MainActor.run { store.trips.first(where: { $0.id == t.id })?.routeMiles }
        #expect(miles == 12.34)
    }
}

@Suite("Breadcrumb export")
struct BreadcrumbExportTests {

    // Create two small JSONL files, combine them, and verify content.
    @Test
    func combineJSONLConcatenatesFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let file1 = dir.appendingPathComponent("trip_a.jsonl")
        let file2 = dir.appendingPathComponent("trip_b.jsonl")

        // Two simple JSON objects per file, each ending with newline.
        let content1 = """
        {"ts":"1970-01-01T00:00:00Z","lat":1.0,"lon":2.0,"hAcc":10}
        {"ts":"1970-01-01T00:01:00Z","lat":1.1,"lon":2.1,"hAcc":12}
        """

        let content2 = """
        {"ts":"1970-01-01T00:02:00Z","lat":3.0,"lon":4.0,"hAcc":8}
        {"ts":"1970-01-01T00:03:00Z","lat":3.1,"lon":4.1,"hAcc":9}
        """

        try (content1 + "\n").data(using: .utf8)?.write(to: file1, options: .atomic)
        try (content2 + "\n").data(using: .utf8)?.write(to: file2, options: .atomic)

        let outURL = try BreadcrumbExporter.combineJSONL(from: [file1, file2], outputName: "combined_test.jsonl")
        let combined = try String(contentsOf: outURL, encoding: .utf8)

        // Expect header line, then all four JSON lines present.
        #expect(combined.contains("# Combined TripPoint JSON Lines"))
        #expect(combined.contains(#""lat":1.0,"lon":2.0"#))
        #expect(combined.contains(#""lat":1.1,"lon":2.1"#))
        #expect(combined.contains(#""lat":3.0,"lon":4.0"#))
        #expect(combined.contains(#""lat":3.1,"lon":4.1"#))

        // Basic sanity: at least 5 lines (1 header + 4 points), ignoring any trailing blank.
        let lines = combined.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count >= 5)
    }

@Suite("Master JSONL (points_master.jsonl)")
    struct MileageMasterJSONLTests {

        // Helper to make a unique temp directory URL for each test
        private func uniqueTempDirectory() -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        }

        @Test("Starting a trip creates points_master.jsonl and pointsMasterFileURL() returns it")
        func masterFileCreatedOnStart() async throws {
            let base = uniqueTempDirectory()
            let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

            await MainActor.run {
                store.startTrip(at: Date(), startLat: nil, startLon: nil)
            }

            // Give any async file ops a brief moment
            try await Task.sleep(nanoseconds: 50_000_000)

            let url = await MainActor.run { store.pointsMasterFileURL() }
            #expect(url != nil)

            // Ensure the file exists on disk
            if let url {
                let exists = FileManager.default.fileExists(atPath: url.path)
                #expect(exists)
            }

            // Cleanup: cancel the trip (does not delete master file)
            await MainActor.run {
                store.cancelCurrentTrip()
            }
        }

        @Test("Finalizing a trip leaves points_master.jsonl in place")
        func masterFilePersistsAfterFinalize() async throws {
            let base = uniqueTempDirectory()
            let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

            await MainActor.run {
                store.startTrip(at: Date(), startLat: nil, startLon: nil)
            }

            // Finalize quickly (no actual points recorded in this test)
            await MainActor.run {
                store.finalizeCurrentTrip(endOdo: 0, endLat: nil, endLon: nil)
            }

            // Give any async file ops a brief moment
            try await Task.sleep(nanoseconds: 50_000_000)

            let url = await MainActor.run { store.pointsMasterFileURL() }
            #expect(url != nil)

            if let url {
                let exists = FileManager.default.fileExists(atPath: url.path)
                #expect(exists)
            }
        }

        @Test("Canceling a trip leaves points_master.jsonl in place")
        func masterFilePersistsAfterCancel() async throws {
            let base = uniqueTempDirectory()
            let store = await MainActor.run { MileageStore(baseDirectoryURL: base) }

            await MainActor.run {
                store.startTrip(at: Date(), startLat: nil, startLon: nil)
                store.cancelCurrentTrip()
            }

            // Give any async file ops a brief moment
            try await Task.sleep(nanoseconds: 50_000_000)

            let url = await MainActor.run { store.pointsMasterFileURL() }
            #expect(url != nil)

            if let url {
                let exists = FileManager.default.fileExists(atPath: url.path)
                #expect(exists)
            }
        }
    }

@Suite("CSVExporter uses Trip.id")
    struct CSVExporterTripIdTests {

        @Test("CSV includes the provided Trip UUID as the id column")
        func csvIncludesTripUUID() {
            var trip = Trip(
                date: Date(timeIntervalSince1970: 0),
                startOdo: 0,
                endOdo: 0,
                purpose: "Test",
                category: "Cat",
                notes: "Note"
            )
            // Set a known UUID so we can assert on it
            let known = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
            trip.id = known

            let csv = CSVExporter.makeCSV(trips: [trip])

            // Expect the UUID string to appear as the first column of the data row
            #expect(csv.contains(known.uuidString))
            // Also sanity-check that the header exists
            #expect(csv.contains(CSVExporter.header))
        }
    }

}


