//
//  CSVExporter.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//

import Foundation

struct CSVExporter {
    // Header row
    // Added id (UUID) as the first column for cross-referencing.
    // start_lat,start_lon,end_lat,end_lon included for auditing and miles_source indicates where miles came from.
    static let header = "id,date_utc,start_odo,end_odo,miles,miles_source,start_lat,start_lon,end_lat,end_lon,destination,purpose,category,notes,created_at_utc"

    // Comment row explaining fields for auditing clarity.
    // Many CSV tools ignore lines starting with '#'.
    static let comment = "# Note: id is the Trip UUID. 'purpose' = Client name, 'category' = Service type. start_odo/end_odo may be blank if no manual odometer was entered. 'miles' is computed (recorded > route > odometer). Coordinates are included when captured. 'miles_source' shows which method was used."

    static func makeCSV(trips: [Trip]) -> String {
        // Sort by date ascending (nice-to-have)
        let sorted = trips.sorted { $0.date < $1.date }
        var lines: [String] = [comment, header]
        let df = iso8601UTCFormatter

        for t in sorted {
            let startOdoField = formattedOptionalNumber(emptyIfZero: t.startOdo)
            let endOdoField = formattedOptionalNumber(emptyIfZero: t.endOdo)

            let startLatField = formattedOptionalCoord(t.startLat)
            let startLonField = formattedOptionalCoord(t.startLon)
            let endLatField   = formattedOptionalCoord(t.endLat)
            let endLonField   = formattedOptionalCoord(t.endLon)

            let miles = t.exportMiles
            let source = milesSourceString(for: t)

            let fields: [String] = [
                t.id.uuidString,
                df.string(from: t.date),
                startOdoField,
                endOdoField,
                formatMiles(miles),
                source,
                startLatField,
                startLonField,
                endLatField,
                endLonField,
                escape(t.destination ?? ""),
                escape(t.purpose),
                escape(t.category),
                escape(t.notes),
                df.string(from: t.createdAt)
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private static var iso8601UTCFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    private static func escape(_ s: String) -> String {
        // Wrap in quotes if contains comma, quote, or newline; escape quotes by doubling
        if s.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) {
            let doubled = s.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(doubled)\""
        } else {
            return s
        }
    }

    // General number formatter used for odometer fields when non-zero.
    // Leaves integers without decimals; otherwise two decimals.
    private static func formatNumber(_ d: Double) -> String {
        if d.rounded(.towardZero) == d {
            return String(format: "%.0f", d)
        } else {
            return String(format: "%.2f", d)
        }
    }

    // Miles must always be two decimals for CSV tests.
    private static func formatMiles(_ d: Double) -> String {
        String(format: "%.2f", d)
    }

    // If value is zero, export an empty field; otherwise format normally.
    private static func formattedOptionalNumber(emptyIfZero d: Double) -> String {
        if d == 0 {
            return ""
        } else {
            return formatNumber(d)
        }
    }

    // Coordinates: format to 5 decimal places (≈1.1m), empty if nil.
    private static func formattedOptionalCoord(_ v: Double?) -> String {
        guard let v = v else { return "" }
        return String(format: "%.5f", v)
    }

    // Determine which method produced exportMiles (recorded > route > odometer).
    private static func milesSourceString(for t: Trip) -> String {
        if let rec = t.recordedMiles, rec > 0 {
            return "recorded"
        }
        if let r = t.routeMiles, r > 0 {
            return "route"
        }
        return "odometer"
    }
}

