//
//  TripPoint.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/16/25.
//

import Foundation
import CoreLocation

struct TripPoint: Hashable {
    // Timestamp of the sample
    var ts: Date

    // Coordinates
    var lat: Double
    var lon: Double

    // Horizontal accuracy in meters (CLLocation.horizontalAccuracy)
    var hAcc: Double

    // Optional speed in m/s (CLLocation.speed); negative means invalid
    var speed: Double?

    // Optional course in degrees (CLLocation.course), 0...360
    var course: Double?

    init(ts: Date, lat: Double, lon: Double, hAcc: Double, speed: Double? = nil, course: Double? = nil) {
        self.ts = ts
        self.lat = lat
        self.lon = lon
        self.hAcc = hAcc
        self.speed = speed
        self.course = course
    }

    init(from location: CLLocation) {
        self.ts = location.timestamp
        self.lat = location.coordinate.latitude
        self.lon = location.coordinate.longitude
        self.hAcc = max(0, location.horizontalAccuracy)
        self.speed = location.speed >= 0 ? location.speed : nil
        if #available(iOS 13.4, watchOS 6.2, *) {
            self.course = location.course >= 0 ? location.course : nil
        } else {
            self.course = nil
        }
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var clLocation: CLLocation {
        CLLocation(latitude: lat, longitude: lon)
    }
}

// Explicit, nonisolated Decodable conformance so decoding can occur off the MainActor.
extension TripPoint: Decodable {
    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.ts = try c.decode(Date.self, forKey: .ts)
        self.lat = try c.decode(Double.self, forKey: .lat)
        self.lon = try c.decode(Double.self, forKey: .lon)
        self.hAcc = try c.decode(Double.self, forKey: .hAcc)
        self.speed = try c.decodeIfPresent(Double.self, forKey: .speed)
        self.course = try c.decodeIfPresent(Double.self, forKey: .course)
    }

    private enum CodingKeys: String, CodingKey {
        case ts, lat, lon, hAcc, speed, course
    }
}

// Encoding is safe to be used anywhere; keep it explicit for symmetry.
extension TripPoint: Encodable {
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ts, forKey: .ts)
        try c.encode(lat, forKey: .lat)
        try c.encode(lon, forKey: .lon)
        try c.encode(hAcc, forKey: .hAcc)
        try c.encodeIfPresent(speed, forKey: .speed)
        try c.encodeIfPresent(course, forKey: .course)
    }
}
