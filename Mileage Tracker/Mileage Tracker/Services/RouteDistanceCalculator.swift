//
//  RouteDistanceCalculator.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import Foundation
import CoreLocation
import MapKit

enum RouteDistanceCalculator {
    // Simple in-memory cache to avoid repeated network calls for identical endpoints.
    // Key uses quantized coordinates to 5 decimal places.
    private static var cache = Cache()

    // Compute driving distance in miles using MapKit Directions.
    // Returns nil if routing fails or inputs are missing.
    static func routeMiles(from start: CLLocationCoordinate2D?, to end: CLLocationCoordinate2D?) async -> Double? {
        guard let start = start, let end = end else { return nil }

        // Check cache first
        let key = CacheKey(start: start, end: end)
        if let cached = await cache.value(for: key) {
            return cached
        }

        let source: MKMapItem
        let dest: MKMapItem

        if #available(iOS 26.0, *) {
            let sourceLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let destLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            source = MKMapItem(location: sourceLocation, address: nil)
            dest = MKMapItem(location: destLocation, address: nil)
        } else {
            let sourcePlacemark = MKPlacemark(coordinate: start)
            let destPlacemark = MKPlacemark(coordinate: end)
            source = MKMapItem(placemark: sourcePlacemark)
            dest = MKMapItem(placemark: destPlacemark)
        }

        let request = MKDirections.Request()
        request.source = source
        request.destination = dest
        request.transportType = .automobile
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        do {
            let response = try await directions.calculate()
            guard let route = response.routes.first else {
                await cache.set(nil, for: key)
                return nil
            }
            let meters = route.distance
            let miles = meters / 1609.344
            let clamped = miles >= 0 ? miles : nil
            await cache.set(clamped, for: key)
            return clamped
        } catch {
            // Network off, no route, or other routing issue
            print("Route calculation failed: \(error)")
            await cache.set(nil, for: key)
            return nil
        }
    }
}

// MARK: - Lightweight cache

// Keep the type simple and Sendable; provide Hashable conformance in a nonisolated extension below.
private struct CacheKey: Sendable {
    let sLat: Int32
    let sLon: Int32
    let eLat: Int32
    let eLon: Int32

    init(start: CLLocationCoordinate2D, end: CLLocationCoordinate2D) {
        func quantize(_ v: Double) -> Int32 {
            // Round to 5 decimal places and scale to integer
            let scaled = (v * 100_000).rounded()
            return Int32(scaled)
        }
        self.sLat = quantize(start.latitude)
        self.sLon = quantize(start.longitude)
        self.eLat = quantize(end.latitude)
        self.eLon = quantize(end.longitude)
    }
}

// Explicitly nonisolated Hashable conformance to avoid @MainActor inference in Swift 6.
nonisolated extension CacheKey: Hashable {
    static func == (lhs: CacheKey, rhs: CacheKey) -> Bool {
        lhs.sLat == rhs.sLat &&
        lhs.sLon == rhs.sLon &&
        lhs.eLat == rhs.eLat &&
        lhs.eLon == rhs.eLon
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(sLat)
        hasher.combine(sLon)
        hasher.combine(eLat)
        hasher.combine(eLon)
    }
}

private actor Cache {
    private var store: [CacheKey: Double?] = [:]

    func value(for key: CacheKey) -> Double?? {
        store[key]
    }

    func set(_ value: Double?, for key: CacheKey) {
        store[key] = value
    }
    static func metersToMiles(_ meters: Double) -> Double {
        meters / 1609.344
    }
}
