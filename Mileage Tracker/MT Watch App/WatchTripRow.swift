//
//  WatchTripRow.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/16/25.
//


import SwiftUI

struct WatchTripRow: View {
    let trip: Trip

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(dateString(trip.date))
                    .font(.caption)
                if !trip.purpose.isEmpty {
                    Text(trip.purpose)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(milesString(trip.exportMiles))
                .font(.caption)
                .monospacedDigit()
        }
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        return f.string(from: date)
    }

    private func milesString(_ miles: Double) -> String {
        String(format: "%.1f", miles)
    }
}
