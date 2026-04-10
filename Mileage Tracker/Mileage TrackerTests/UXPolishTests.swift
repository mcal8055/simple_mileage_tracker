import Testing
@testable import Mileage_Tracker
internal import Foundation
import CoreLocation

// MARK: - Configurable Services

@Suite("MileageStore Services list")
@MainActor
struct MileageStoreServicesTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServicesTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Add services are unique (case-insensitive) and sorted")
    func addUniqueAndSorted() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)
        // Wait for defaults to seed via loadServices()
        try await Task.sleep(nanoseconds: 200_000_000)

        let countBefore = store.services.count
        store.addService("New Custom Service")
        store.addService("NEW CUSTOM SERVICE") // duplicate — should be ignored

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.services.count == countBefore + 1)
        let lowered = Set(store.services.map { $0.lowercased() })
        #expect(lowered.count == store.services.count) // no dupes
    }

    @Test("Remove service removes by case-insensitive match")
    func removeService() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)
        // Wait for defaults to seed
        try await Task.sleep(nanoseconds: 200_000_000)

        let countBefore = store.services.count
        store.removeService(named: "dog walking") // case-insensitive match for default

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(store.services.count == countBefore - 1)
        #expect(!store.services.contains(where: { $0.caseInsensitiveCompare("Dog Walking") == .orderedSame }))
    }

    @Test("Services persist to disk and reload")
    func servicesPersist() async throws {
        let dir = try makeTempDirectory()
        do {
            let store = MileageStore(baseDirectoryURL: dir)
            // Wait for defaults to seed
            try await Task.sleep(nanoseconds: 200_000_000)
            store.addService("Custom Service")
            try await Task.sleep(nanoseconds: 200_000_000)
            _ = store
        }

        let store2 = MileageStore(baseDirectoryURL: dir)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Should have defaults + our custom one
        #expect(store2.services.contains(where: { $0.caseInsensitiveCompare("Custom Service") == .orderedSame }))
        #expect(store2.services.contains(where: { $0.caseInsensitiveCompare("House Sitting") == .orderedSame }))
    }

    @Test("Services seed with defaults on first launch")
    func defaultServicesSeedOnFirstLaunch() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)
        try await Task.sleep(nanoseconds: 200_000_000)

        // Should have the 4 default services
        #expect(store.services.count == 4)
        #expect(store.services.contains("House Sitting"))
        #expect(store.services.contains("Drop-ins"))
        #expect(store.services.contains("Dog Walking"))
        #expect(store.services.contains("Meet & Greet"))
    }

    @Test("Empty service name is not added")
    func emptyServiceNotAdded() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)

        let initialCount = store.services.count
        store.addService("")
        store.addService("   ")

        #expect(store.services.count == initialCount)
    }
}

// MARK: - Destination field

@Suite("Trip destination field")
struct TripDestinationTests {

    @Test("Destination defaults to nil for backward compatibility")
    func destinationDefaultsNil() {
        let t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        #expect(t.destination == nil)
    }

    @Test("Destination survives Codable round-trip")
    func destinationCodableRoundTrip() throws {
        var t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        t.destination = "123 Main St, Salt Lake City, UT"

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(t)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Trip.self, from: data)

        #expect(decoded.destination == "123 Main St, Salt Lake City, UT")
    }

    @Test("Decoding old JSON without destination field succeeds with nil")
    func decodingOldJSONWithoutDestination() throws {
        // Simulate pre-destination JSON
        let json = """
        {
            "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
            "date": "2024-10-10T10:10:10Z",
            "startOdo": 100, "endOdo": 120,
            "purpose": "Test", "category": "Biz", "notes": "",
            "createdAt": "2024-10-10T10:10:10Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let t = try decoder.decode(Trip.self, from: Data(json.utf8))

        #expect(t.destination == nil)
        #expect(t.purpose == "Test")
    }
}

// MARK: - CSV destination column

@Suite("CSVExporter destination column")
struct CSVExporterDestinationTests {

    @Test("CSV header includes destination column")
    func headerIncludesDestination() {
        #expect(CSVExporter.header.contains("destination"))
    }

    @Test("CSV row includes destination value")
    func rowIncludesDestination() {
        var t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "Alice", category: "Walking", notes: "")
        t.destination = "456 Oak Ave, Provo, UT"

        let csv = CSVExporter.makeCSV(trips: [t])
        #expect(csv.contains("456 Oak Ave"))
        #expect(csv.contains("Provo"))
    }

    @Test("CSV row has empty field when destination is nil")
    func rowEmptyWhenNil() {
        let t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "Bob", category: "Sitting", notes: "")
        let csv = CSVExporter.makeCSV(trips: [t])

        // destination column should be empty (two consecutive commas around it)
        let lines = csv.split(separator: "\n").dropFirst(2)
        guard let row = lines.first else {
            Issue.record("No data row found")
            return
        }
        let fields = row.split(separator: ",", omittingEmptySubsequences: false)
        // destination is at index 10 (after end_lon)
        #expect(fields.count >= 15) // id + 14 other columns
        #expect(fields[10] == "") // destination empty
    }

    @Test("Destination with commas is properly escaped in CSV")
    func destinationEscaped() {
        var t = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        t.destination = "123 Main St, Suite 4, City"

        let csv = CSVExporter.makeCSV(trips: [t])
        // Should be wrapped in quotes due to commas
        #expect(csv.contains("\"123 Main St, Suite 4, City\""))
    }
}

// MARK: - EditTripViewModel destination

@Suite("EditTripViewModel destination")
@MainActor
struct EditTripViewModelDestinationTests {

    @Test("Destination loaded from trip and saved back")
    func destinationRoundTrip() {
        var trip = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        trip.destination = "789 Elm St, Ogden, UT"

        let vm = EditTripViewModel(trip: trip)
        #expect(vm.destination == "789 Elm St, Ogden, UT")

        let saved = vm.makeTrip()
        #expect(saved.destination == "789 Elm St, Ogden, UT")
    }

    @Test("Nil destination loads as empty string in VM")
    func nilDestinationLoadsEmpty() {
        let trip = Trip(date: .now, startOdo: 0, endOdo: 0, purpose: "", category: "", notes: "")
        let vm = EditTripViewModel(trip: trip)
        #expect(vm.destination == "")
    }

    @Test("Whitespace-only destination saves as nil")
    func whitespaceDestinationSavesNil() {
        let vm = EditTripViewModel(trip: nil)
        vm.destination = "   "
        let saved = vm.makeTrip()
        #expect(saved.destination == nil)
    }
}

// MARK: - Crash recovery

@Suite("MileageStore crash recovery")
@MainActor
struct CrashRecoveryTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrashRecoveryTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Recorder resumes on relaunch when trip_in_progress.json exists")
    func recorderResumesOnRelaunch() async throws {
        let dir = try makeTempDirectory()

        // First store: start a trip, then "crash" (just let it go without finalizing)
        do {
            let store = MileageStore(baseDirectoryURL: dir)
            store.startTrip(at: Date(), startLat: 40.0, startLon: -111.0)
            // Wait for async save of trip_in_progress.json
            try await Task.sleep(nanoseconds: 200_000_000)
            // Simulate crash: cancel recorder without clearing in-progress file
            _ = store
        }

        // Verify trip_in_progress.json was written
        let ipURL = dir.appendingPathComponent("trip_in_progress.json")
        #expect(FileManager.default.fileExists(atPath: ipURL.path))

        // Second store: simulates relaunch — should load in-progress and resume recording
        let store2 = MileageStore(baseDirectoryURL: dir)
        try await Task.sleep(nanoseconds: 300_000_000)

        #expect(store2.currentTripInProgress != nil)
        // The points directory should exist from the resumed recording
        let pointsDir = dir.appendingPathComponent("points", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: pointsDir.path))
    }
}

// MARK: - Finalize with destination

@Suite("MileageStore finalize with destination")
@MainActor
struct FinalizeDestinationTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FinalizeDestTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Finalize stores destination on the trip")
    func finalizeStoresDestination() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)

        store.startTrip(at: Date(), startLat: nil, startLon: nil)
        store.finalizeCurrentTrip(endOdo: 0, endLat: nil, endLon: nil, destination: "100 State St, SLC, UT")

        #expect(store.trips.count == 1)
        #expect(store.trips.first?.destination == "100 State St, SLC, UT")
    }

    @Test("Finalize without destination leaves it nil")
    func finalizeWithoutDestination() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)

        store.startTrip(at: Date(), startLat: nil, startLon: nil)
        store.finalizeCurrentTrip(endOdo: 0, endLat: nil, endLon: nil)

        #expect(store.trips.first?.destination == nil)
    }
}

// MARK: - LocationRecordingController isRecording

@Suite("LocationRecordingController isRecording")
@MainActor
struct RecorderIsRecordingTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecorderTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("isRecording is false before start and after stop")
    func isRecordingLifecycle() throws {
        let dir = try makeTempDirectory()
        let recorder = LocationRecordingController()

        #expect(!recorder.isRecording)

        try recorder.start(for: UUID(), baseDirectory: dir)
        #expect(recorder.isRecording)

        _ = recorder.stop(cancel: false)
        #expect(!recorder.isRecording)
    }
}
