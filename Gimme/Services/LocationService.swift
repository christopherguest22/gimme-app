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
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?

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

    /// One fix outside a round, so Home can tell which course the golfer is standing on.
    func refresh() {
        guard !isSimulating, authorization == .authorizedWhenInUse || authorization == .authorizedAlways else { return }
        manager.requestLocation()
    }

    /// Full-accuracy updates during a round, kept running with the phone in a pocket so drops
    /// still unlock (needs the "location" background mode). Stopped afterwards to save battery.
    func startRound() {
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = true
        manager.pausesLocationUpdatesAutomatically = false
        if backgroundSession == nil { backgroundSession = CLBackgroundActivitySession() }
        manager.startUpdatingLocation()
    }

    func stopRound() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        backgroundSession?.invalidate()
        backgroundSession = nil
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
