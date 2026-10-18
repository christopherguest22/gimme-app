import CoreLocation

/// A latitude/longitude pair that is Codable and Hashable (CLLocationCoordinate2D is neither).
struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(_ latitude: Double, _ longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(coordinate.latitude, coordinate.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// Distance and bearing helpers used by the GPS screens and the drop geofence.
enum Geo {
    static let metersPerYard = 0.9144
    private static let earthRadius = 6_371_000.0

    static func meters(_ a: Coordinate, _ b: Coordinate) -> Double {
        a.location.distance(from: b.location)
    }

    static func yards(_ a: Coordinate, _ b: Coordinate) -> Int {
        Int((meters(a, b) / metersPerYard).rounded())
    }

    /// Initial compass bearing from a to b, in degrees (0 = north).
    static func bearing(from a: Coordinate, to b: Coordinate) -> Double {
        let lat1 = a.latitude.radians, lat2 = b.latitude.radians
        let dLon = (b.longitude - a.longitude).radians
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x).degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point `meters` away from `start` along compass `bearing`.
    static func offset(_ start: Coordinate, meters: Double, bearing: Double) -> Coordinate {
        let d = meters / earthRadius
        let b = bearing.radians
        let lat1 = start.latitude.radians, lon1 = start.longitude.radians
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
        let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return Coordinate(lat2.degrees, lon2.degrees)
    }

    /// Flat x/y in meters relative to `origin`. Accurate enough at golf-hole scale.
    static func local(_ p: Coordinate, origin: Coordinate) -> (x: Double, y: Double) {
        let x = (p.longitude - origin.longitude).radians * earthRadius * cos(origin.latitude.radians)
        let y = (p.latitude - origin.latitude).radians * earthRadius
        return (x, y)
    }

    /// How far `p` sits along the line from `a` toward `b`, in meters (negative if behind `a`).
    static func along(_ p: Coordinate, from a: Coordinate, toward b: Coordinate) -> Double {
        let v = local(b, origin: a), w = local(p, origin: a)
        let len = (v.x * v.x + v.y * v.y).squareRoot()
        guard len > 0 else { return 0 }
        return (w.x * v.x + w.y * v.y) / len
    }

    /// Shortest distance from `p` to the segment a–b, in meters.
    static func distanceToSegment(_ p: Coordinate, _ a: Coordinate, _ b: Coordinate) -> Double {
        let v = local(b, origin: a), w = local(p, origin: a)
        let len2 = v.x * v.x + v.y * v.y
        let t = len2 > 0 ? max(0, min(1, (w.x * v.x + w.y * v.y) / len2)) : 0
        let dx = w.x - t * v.x, dy = w.y - t * v.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Halfway between two points, for distance labels on a line.
    static func midpoint(_ a: Coordinate, _ b: Coordinate) -> Coordinate {
        Coordinate((a.latitude + b.latitude) / 2, (a.longitude + b.longitude) / 2)
    }

    static func centroid(_ points: [Coordinate]) -> Coordinate? {
        guard !points.isEmpty else { return nil }
        let lat = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let lon = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return Coordinate(lat, lon)
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
