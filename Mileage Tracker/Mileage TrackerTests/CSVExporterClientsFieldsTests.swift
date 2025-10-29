import Testing
@testable import Mileage_Tracker
internal import Foundation

@Suite("CSVExporter includes Client (purpose) and Service (category)")
struct CSVExporterClientsFieldsTests {

    @Test("CSV contains purpose and category values in rows")
    func csvContainsFields() async throws {
        let t = Trip(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            date: ISO8601DateFormatter().date(from: "2024-10-10T10:10:10Z")!,
            endDate: nil,
            startOdo: 0, endOdo: 0,
            purpose: "Alice",     // Client
            category: "Dog Walking", // Service
            notes: "N/A",
            createdAt: ISO8601DateFormatter().date(from: "2024-10-10T10:10:10Z")!,
            startLat: nil, startLon: nil, endLat: nil, endLon: nil,
            routeMiles: nil, recordedMiles: 3.25,
            pointsFileName: nil, pointsCount: 10
        )

        let csv = CSVExporter.makeCSV(trips: [t])

        // Header should include purpose and category columns (already true)
        #expect(csv.contains("purpose"))
        #expect(csv.contains("category"))

        // Row should contain our values (quoted if needed)
        #expect(csv.contains("Alice"))
        #expect(csv.contains("Dog Walking"))
    }
}
