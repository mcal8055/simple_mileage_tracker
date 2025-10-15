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
    var startOdo: Double
    var endOdo: Double
    var purpose: String
    var category: String
    var notes: String
    var createdAt: Date = Date()

    // Optional location capture (explicit, user-triggered)
    var startLat: Double?
    var startLon: Double?
    var endLat: Double?
    var endLon: Double?

    // Persisted route distance (miles) computed via MapKit Directions
    var routeMiles: Double?

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
    // 1) routeMiles (Directions), 2) odometer miles
    // Note: Haversine is intentionally not used.
    var exportMiles: Double {
        if let r = routeMiles { return max(0, r) }
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
