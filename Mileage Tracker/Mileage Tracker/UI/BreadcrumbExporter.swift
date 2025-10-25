//
//  BreadcrumbExporter.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/17/25.
//

import Foundation

enum BreadcrumbExporter {
    // Create a combined NDJSON (.jsonl) file by concatenating the given source files.
    // Returns the URL of the combined file in the temporary directory.
    static func combineJSONL(from urls: [URL], outputName: String? = nil) throws -> URL {
        let name = outputName ?? "points_all_\(timestamp()).jsonl"
        let dir = FileManager.default.temporaryDirectory
        let outURL = dir.appendingPathComponent(name)

        // Overwrite any existing file.
        if FileManager.default.fileExists(atPath: outURL.path) {
            try FileManager.default.removeItem(at: outURL)
        }
        FileManager.default.createFile(atPath: outURL.path, contents: nil)

        let outHandle = try FileHandle(forWritingTo: outURL)
        defer { try? outHandle.close() }

        // Optional header for human context; JSONL consumers ignore it if they expect pure JSON lines.
        if let headerData = "# Combined TripPoint JSON Lines (concatenated)\n".data(using: .utf8) {
            outHandle.write(headerData)
        }

        // Append each source file verbatim using streaming reads.
        for url in urls {
            let inHandle = try FileHandle(forReadingFrom: url)
            defer { try? inHandle.close() }

            while let chunk = try inHandle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                outHandle.write(chunk)
            }
            // Ensure separation newline between files (tolerant if the file already ends with newline).
            if let nl = "\n".data(using: .utf8) {
                outHandle.write(nl)
            }
        }

        return outURL
    }

    private static func timestamp() -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return f.string(from: Date())
    }
}
