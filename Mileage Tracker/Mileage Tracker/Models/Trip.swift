//
//  Trip.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import Foundation
import CoreLocation

struct Trip: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var date: Date
    var endDate: Date? = nil
    var startOdo: Double
    var endOdo: Double
    var purpose: String    // UI label: "Client" — the client/customer name
    var category: String   // UI label: "Service" — the type of service performed
    var notes: String
    var destination: String?       // Reverse-geocoded or user-entered trip destination (IRS requirement)
    var createdAt: Date = Date()

    // Optional location capture (explicit, user-triggered)
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?

    // Persisted route distance (miles) computed via MapKit Directions
    var routeMiles: Double?

    // Recorded breadcrumb distance (miles) computed from sampled TripPoints
    // Preferred for audit/export when available.
    var recordedMiles: Double?

    // Link to per-trip breadcrumb file under baseDirectory/points/
    // Example: "trip_<UUID>.jsonl"
    var pointsFileName: String?

    // Optional quick summary of how many points were recorded
    var pointsCount: Int?

    // Odometer-based miles (kept for compatibility if you ever enter odos)
    var miles: Double {
        max(0, endOdo - startOdo)
    }

    // Haversine distance (straight-line) in miles, if coords exist.
    // Kept for potential diagnostics, but not used for export/display.
    var haversineMiles: Double? {
        guard let slat = startLat, let slon = startLon,
              let elat = endLat, let elon = endLon else { return nil }
        let loc1 = CLLocation(latitude: slat, longitude: slon)
        let loc2 = CLLocation(latitude: elat, longitude: elon)
        let meters = loc1.distance(from: loc2)
        return meters / 1609.344
    }

    // Preferred export/display miles:
    // 1) recordedMiles (from breadcrumbs)
    // 2) routeMiles (Directions)
    // 3) odometer miles
    var exportMiles: Double {
        if let r = recordedMiles, r > 0 { return r }
        if let r = routeMiles, r > 0 { return r }
        return miles
    }
}

extension Trip {
    static let sample = Trip(
        date: Date(),
        startOdo: 12000,
        endOdo: 12015.6,
        purpose: "Client visit",
        category: "Business",
        notes: "Downtown"
    )
}

