//
//  ReverseGeocoder.swift
//  Mileage Tracker
//

import Foundation
import CoreLocation
import MapKit

/// Shared reverse geocoding utility. Uses MKReverseGeocodingRequest on iOS 26+,
/// falls back to CLGeocoder on older versions.
enum ReverseGeocoder {

    /// Returns a compact address string ("123 Main St, City, ST") for the given location, or nil on failure.
    static func reverseGeocode(_ location: CLLocation) async -> String? {
        if #available(iOS 26.0, *) {
            return await reverseGeocodeModern(location)
        } else {
            return await reverseGeocodeLegacy(location)
        }
    }

    // MARK: - iOS 26+ (MapKit)

    @available(iOS 26.0, *)
    private static func reverseGeocodeModern(_ location: CLLocation) async -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        do {
            let mapItems = try await request.mapItems
            guard let item = mapItems.first, let address = item.address else { return nil }
            // MKAddress provides shortAddress which is a compact representation.
            guard let short = address.shortAddress, !short.isEmpty else { return nil }
            return short
        } catch {
            print("Reverse geocode (MapKit) failed: \(error)")
            return nil
        }
    }

    // MARK: - Legacy (CLGeocoder)

    private static func reverseGeocodeLegacy(_ location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let p = placemarks.first else { return nil }
            var parts: [String] = []
            if let street = p.thoroughfare {
                if let number = p.subThoroughfare {
                    parts.append("\(number) \(street)")
                } else {
                    parts.append(street)
                }
            }
            if let city = p.locality { parts.append(city) }
            if let state = p.administrativeArea { parts.append(state) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        } catch {
            print("Reverse geocode (CLGeocoder) failed: \(error)")
            return nil
        }
    }
}
