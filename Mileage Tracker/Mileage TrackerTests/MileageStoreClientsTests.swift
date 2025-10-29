import Testing
@testable import Mileage_Tracker
internal import Foundation

@Suite("MileageStore Clients list")
@MainActor
struct MileageStoreClientsTests {

    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("MileageStoreClientsTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Add clients are unique (case-insensitive) and sorted")
    func addUniqueAndSorted() async throws {
        let dir = try makeTempDirectory()
        let store = MileageStore(baseDirectoryURL: dir)

        // Add clients with mixed cases and verify uniqueness + sort
        store.addClient("Charlie")
        store.addClient("alice")
        store.addClient("Bob")
        store.addClient("ALICE") // duplicate, different case — should be ignored
        store.addClient("  Bob  ") // duplicate with whitespace — should be ignored

        // Allow async save to kick in (Published didSet -> Task)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        #expect(store.clients == ["alice", "Bob", "Charlie"].sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
        // Plus: confirm no dupes
        let set = Set(store.clients.map { $0.lowercased() })
        #expect(set.count == store.clients.count)
    }

    @Test("Clients persist to disk and reload")
    func clientsPersist() async throws {
        let dir = try makeTempDirectory()
        do {
            let store = MileageStore(baseDirectoryURL: dir)
            store.addClient("Alice")
            store.addClient("Bob")
            try await Task.sleep(nanoseconds: 150_000_000)
            // store deinit not strictly necessary; we reinit with same dir
            _ = store
        }

        // Reinitialize store; it should load clients.json
        let store2 = MileageStore(baseDirectoryURL: dir)
        // Give the async loader a moment
        try await Task.sleep(nanoseconds: 150_000_000)

        // Loaded values should be present
        #expect(store2.clients.contains(where: { $0.caseInsensitiveCompare("Alice") == .orderedSame }))
        #expect(store2.clients.contains(where: { $0.caseInsensitiveCompare("Bob") == .orderedSame }))
    }
}
