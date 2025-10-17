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
            if let point = try? decoder.decode(TripPoint.self, from: data) {
                coords.append(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
            }
        }

        return coords
    }
}
