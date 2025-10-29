// TripPointsReader.swift
// Mileage Tracker

import Foundation
import CoreLocation

actor TripPointsReader {
    // Stream a JSONL file and decode TripPoint per line.
    func loadPoints(from url: URL) async throws -> [CLLocationCoordinate2D] {
        var coords: [CLLocationCoordinate2D] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Use an InputStream for large files to avoid loading all into memory
        guard let stream = InputStream(url: url) else { return [] }
        stream.open()
        defer { stream.close() }

        // Read in chunks and split by newline
        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        func processLines() {
            while let range = data.firstRange(of: Data([0x0A])) { // newline
                let lineData = data.subdata(in: data.startIndex..<range.lowerBound)
                data.removeSubrange(data.startIndex...range.lowerBound)

                guard !lineData.isEmpty else { continue }
                // Skip comment/header lines that start with '#'
                if lineData.first == UInt8(ascii: "#") { continue }

                if let point = try? decoder.decode(TripPoint.self, from: lineData) {
                    coords.append(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
                }
            }
        }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
                processLines()
            } else {
                break
            }
        }

        // Process any trailing line without newline
        if !data.isEmpty {
            // Skip trailing comment/header if present
            if data.first != UInt8(ascii: "#"),
               let point = try? decoder.decode(TripPoint.self, from: data) {
                coords.append(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
            }
        }

        return coords
    }

    // Stream the master JSONL and collect coordinates for a specific tripId.
    // Each line is a flat JSON object containing at least: tripId, ts, lat, lon, hAcc, [speed], [course].
    func loadPointsFromMaster(_ url: URL, forTripId tripId: UUID) async throws -> [CLLocationCoordinate2D] {
        struct EncodedPointLite: Decodable {
            let tripId: UUID
            let lat: Double
            let lon: Double
        }

        var coords: [CLLocationCoordinate2D] = []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let stream = InputStream(url: url) else { return [] }
        stream.open()
        defer { stream.close() }

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        var data = Data()
        func processLines() {
            while let range = data.firstRange(of: Data([0x0A])) { // newline
                let lineData = data.subdata(in: data.startIndex..<range.lowerBound)
                data.removeSubrange(data.startIndex...range.lowerBound)

                guard !lineData.isEmpty else { continue }
                // Skip comment/header lines that start with '#'
                if lineData.first == UInt8(ascii: "#") { continue }

                if let ep = try? decoder.decode(EncodedPointLite.self, from: lineData), ep.tripId == tripId {
                    coords.append(CLLocationCoordinate2D(latitude: ep.lat, longitude: ep.lon))
                }
            }
        }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
                processLines()
            } else {
                break
            }
        }

        // Process any trailing line without newline
        if !data.isEmpty {
            if data.first != UInt8(ascii: "#"),
               let ep = try? decoder.decode(EncodedPointLite.self, from: data),
               ep.tripId == tripId {
                coords.append(CLLocationCoordinate2D(latitude: ep.lat, longitude: ep.lon))
            }
        }

        return coords
    }
}

