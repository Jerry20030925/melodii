import Foundation
import CoreLocation
import Combine

@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published var currentCity: String?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isLocating: Bool = false
    @Published var locationError: String?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private var originalAccuracy: CLLocationAccuracy = kCLLocationAccuracyHundredMeters
    private var boosted: Bool = false
    private var locationTimeout: Task<Void, Never>?

    // 缓存最后的位置，避免频繁请求
    private var lastLocation: CLLocation?
    private var lastCityFetchTime: Date?
    private let cityCacheTime: TimeInterval = 300 // 5分钟缓存

    private override init() {
        super.init()
        manager.delegate = self
        // 使用更快的精度设置
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        originalAccuracy = manager.desiredAccuracy
    }

    func requestCity() {
        // 检查缓存是否有效
        if let lastCity = currentCity,
           let lastTime = lastCityFetchTime,
           Date().timeIntervalSince(lastTime) < cityCacheTime {
            print("✅ 使用缓存的城市: \(lastCity)")
            return // 使用缓存的城市
        }

        // 清除之前的错误
        locationError = nil
        isLocating = true

        // 检查权限状态
        let status = manager.authorizationStatus
        if status == .denied || status == .restricted {
            locationError = "位置权限未授权，请在设置中开启"
            isLocating = false
            return
        }

        // 使用千米级精度，更快响应
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.desiredAccuracy = kCLLocationAccuracyKilometer
            manager.requestLocation()
        } else {
            // 请求权限
            manager.requestWhenInUseAuthorization()
        }

        // 设置8秒超时（缩短超时时间）
        locationTimeout?.cancel()
        locationTimeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000) // 8秒
            if isLocating {
                isLocating = false
                locationError = "定位超时，请检查网络或位置权限"
            }
        }
    }

    private func boostAccuracy() {
        guard !boosted else { return }
        boosted = true
        originalAccuracy = manager.desiredAccuracy
        // 使用最佳精度以获得最快的首次定位
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    private func restoreAccuracy() {
        guard boosted else { return }
        manager.desiredAccuracy = originalAccuracy
        boosted = false
    }

    func stopLocating() {
        isLocating = false
        locationTimeout?.cancel()
        restoreAccuracy()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                // 如果正在定位中，立即请求位置
                if self.isLocating {
                    self.boostAccuracy()
                    manager.requestLocation()
                }
            } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.isLocating = false
                self.locationError = "位置权限未授权，请在设置中开启"
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("定位失败: \(error)")
        Task { @MainActor in
            self.isLocating = false
            self.locationError = "定位失败：\(error.localizedDescription)"
            self.locationTimeout?.cancel()
            self.restoreAccuracy()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        Task { @MainActor in
            // 取消超时任务
            self.locationTimeout?.cancel()
        }

        geocoder.reverseGeocodeLocation(loc) { [weak self] placemarks, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    print("❌ 反向地理编码失败: \(error)")
                    self.locationError = "地理编码失败，请重试"
                    self.isLocating = false
                } else {
                    let place = placemarks?.first
                    let city = place?.locality ?? place?.subAdministrativeArea ?? place?.administrativeArea
                    if let city {
                        self.currentCity = city
                        self.lastLocation = loc
                        self.lastCityFetchTime = Date() // 记录缓存时间
                        self.locationError = nil
                        print("✅ 定位成功: \(city)")
                    } else {
                        self.locationError = "无法获取城市信息"
                    }
                    self.isLocating = false
                }
                self.restoreAccuracy()
            }
        }
    }
}