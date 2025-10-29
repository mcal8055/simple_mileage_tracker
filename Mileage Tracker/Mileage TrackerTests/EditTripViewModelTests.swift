import Testing
@testable import Mileage_Tracker
internal import Foundation

@Suite("EditTripViewModel mapping")
@MainActor
struct EditTripViewModelTests {

    @Test("Service maps to Trip.category and Client maps to Trip.purpose")
    func mappingServiceAndClient() async throws {
        // New trip
        let vm = EditTripViewModel(trip: nil)
        // Service and Client (UI dropdowns)
        vm.category = "Dog Walking" // Service
        vm.purpose = "Alice"        // Client
        vm.notes = "Evening visit"

        let trip = vm.makeTrip()

        #expect(trip.category == "Dog Walking")
        #expect(trip.purpose == "Alice")
        #expect(trip.notes == "Evening visit")
    }

    @Test("Trimming whitespace when saving")
    func trimmingWhitespace() async throws {
        let vm = EditTripViewModel(trip: nil)
        vm.category = "  Drop-ins  "
        vm.purpose = "  Bob "
        vm.notes = "  Note  "

        let trip = vm.makeTrip()

        #expect(trip.category == "Drop-ins")
        #expect(trip.purpose == "Bob")
        #expect(trip.notes == "Note")
    }
}
