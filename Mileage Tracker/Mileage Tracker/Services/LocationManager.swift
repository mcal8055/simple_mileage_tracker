
//
//  LocationManager.swift
//  Mileage Tracker
//
//  Created by Josh McAlister on 10/15/25.
//
Ok, 
import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationManager: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle
        case requesting
        case authorized
        case denied
        case failed(String)
        case gotFix(CLLocation)
    }

    @Published private(set) var status: Status = .idle

    private let manager = CLLocationManager()
    private var pendingFixContinuation: CheckedContinuation<CLLocation?, Never>?
    private var timeoutTask: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50 // meters
    }

    func requestWhenInUseAuthorization() {
        let auth = CLLocationManager.authorizationStatus()
        switch auth {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied:
            status = .denied
        case .authorizedWhenInUse, .authorizedAlways:
            status = .authorized
        @unknown default:
            status = .denied
        }
    }

    // One-shot location capture with timeout (~10s)
    func captureOneShotLocation(timeout seconds: TimeInterval = 10) async -> CLLocation? {
        // Ensure authorized (or ask)
        let auth = CLLocationManager.authorizationStatus()
        if auth == .notDetermined {
            requestWhenInUseAuthorization()
            // Give the delegate a moment to update status; user may need to respond.
            // The UI should allow a second tap if permission is granted afterward.
        } else if auth == .denied || auth == .restricted {
            status = .denied
            return nil
        }

        status = .requesting
        manager.startUpdatingLocation()

        // Timeout
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            await self?.handleTimeout()
        }

        return await withCheckedContinuation { continuation in
            self.pendingFixContinuation = continuation
        }
    }

    private func finish(with location: CLLocation?) {
        manager.stopUpdatingLocation()
        timeoutTask?.cancel()
        timeoutTask = nil

        if let loc = location {
            status = .gotFix(loc)
            pendingFixContinuation?.resume(returning: loc)
        } else {
            if case .denied = status {
                // keep denied status
            } else {
                status = .failed("No location fix")
            }
            pendingFixContinuation?.resume(returning: nil)
        }
        pendingFixContinuation = nil
    }

    private func handleTimeout() {
        // Called on MainActor via Task above
        guard pendingFixContinuation != nil else { return }
        finish(with: nil)
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let auth = CLLocationManager.authorizationStatus()
            switch auth {
            case .authorizedWhenInUse, .authorizedAlways:
                status = .authorized
            case .denied, .restricted:
                status = .denied
            case .notDetermined:
                status = .idle
            @unknown default:
                status = .denied
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            status = .failed(error.localizedDescription)
            finish(with: nil)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            if let loc = locations.last {
                finish(with: loc)
            }
        }
    }
}
