import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentCity: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private var originalAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    private var boosted: Bool = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        originalAccuracy = manager.desiredAccuracy
    }

    func requestCity() {
        // 提升精度以更快更准
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            boostAccuracy()
        }
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    private func boostAccuracy() {
        guard !boosted else { return }
        boosted = true
        originalAccuracy = manager.desiredAccuracy
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    private func restoreAccuracy() {
        guard boosted else { return }
        manager.desiredAccuracy = originalAccuracy
        boosted = false
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                boostAccuracy()
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("定位失败: \(error)")
        Task { @MainActor in
            self.restoreAccuracy()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self else { return }
            if let error { print("反向地理编码失败: \(error)") }
            let place = placemarks?.first
            let city = place?.locality ?? place?.subAdministrativeArea ?? place?.administrativeArea
            Task { @MainActor in
                if let city { self.currentCity = city }
                self.restoreAccuracy()
            }
        }
    }
}