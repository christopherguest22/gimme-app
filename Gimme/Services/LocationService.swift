import CoreLocation
import Observation

/// Wraps CoreLocation for the round. `simulate(_:)` lets you walk the course from the
/// Simulator or a couch: while a simulated point is set, real GPS fixes are ignored.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var coordinate: Coordinate?
    private(set) var accuracyMeters: Double?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var isSimulating = false

    private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2
        manager.activityType = .fitness
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    /// Full-accuracy updates during a round; stop afterwards to save battery.
    func startRound() {
        manager.startUpdatingLocation()
    }

    func stopRound() {
        manager.stopUpdatingLocation()
    }

    func simulate(_ point: Coordinate?) {
        isSimulating = point != nil
        if let point {
            coordinate = point
            accuracyMeters = 3
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if authorization == .authorizedWhenInUse || authorization == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !isSimulating, let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        coordinate = Coordinate(latest.coordinate)
        accuracyMeters = latest.horizontalAccuracy
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Keep the last good fix; a single failed update is common on the course.
    }
}
