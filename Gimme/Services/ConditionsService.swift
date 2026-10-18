import Foundation

/// Live wind and temperature, plus ground elevation for tees and greens, from Open-Meteo.
/// Free with no key for non-commercial use; a paid plan (customer-api.open-meteo.com) is
/// needed once the app makes money.
struct ConditionsService {
    var forecastURL = URL(string: "https://api.open-meteo.com/v1/forecast")!
    var elevationURL = URL(string: "https://api.open-meteo.com/v1/elevation")!

    func current(at point: Coordinate) async throws -> Conditions {
        var components = URLComponents(url: forecastURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(point.latitude)"),
            URLQueryItem(name: "longitude", value: "\(point.longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,wind_speed_10m,wind_direction_10m"),
            URLQueryItem(name: "wind_speed_unit", value: "mph"),
            URLQueryItem(name: "temperature_unit", value: "fahrenheit"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let response = try JSONDecoder().decode(ForecastResponse.self, from: data)
        return Conditions(windMph: response.current.wind_speed_10m,
                          windFromDegrees: response.current.wind_direction_10m,
                          temperatureF: response.current.temperature_2m)
    }

    /// Ground heights in meters for many points in one call (Open-Meteo allows 100 per request).
    func elevations(_ points: [Coordinate]) async throws -> [Double] {
        var result: [Double] = []
        for start in stride(from: 0, to: points.count, by: 100) {
            let chunk = points[start..<min(start + 100, points.count)]
            var components = URLComponents(url: elevationURL, resolvingAgainstBaseURL: false)!
            components.queryItems = [
                URLQueryItem(name: "latitude", value: chunk.map { String($0.latitude) }.joined(separator: ",")),
                URLQueryItem(name: "longitude", value: chunk.map { String($0.longitude) }.joined(separator: ",")),
            ]
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            result += try JSONDecoder().decode(ElevationResponse.self, from: data).elevation
        }
        return result
    }

    /// Fills in tee and green heights for every hole so plays-like distances include elevation.
    func addElevation(to course: Course) async -> Course {
        var course = course
        let points = course.holes.flatMap { [$0.tee, $0.greenCenter] }
        guard let heights = try? await elevations(points), heights.count == points.count else { return course }
        for i in course.holes.indices {
            course.holes[i].teeElevation = heights[i * 2]
            course.holes[i].greenElevation = heights[i * 2 + 1]
        }
        return course
    }

    /// Height of one point, for the golfer's own position.
    func elevation(at point: Coordinate) async -> Double? {
        try? await elevations([point]).first
    }
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        var temperature_2m: Double
        var wind_speed_10m: Double
        var wind_direction_10m: Double
    }
    var current: Current
}

private struct ElevationResponse: Decodable {
    var elevation: [Double]
}
