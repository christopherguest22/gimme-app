import Foundation

/// Weather at the course right now, from Open-Meteo.
struct Conditions: Codable, Hashable {
    var windMph: Double
    /// Compass direction the wind blows FROM, in degrees (0 = from the north).
    var windFromDegrees: Double
    var temperatureF: Double
}

/// "Plays like" yardage: the real distance adjusted for elevation, wind and temperature,
/// using common caddie rules of thumb (the same factors 18Birdies lists):
/// - Elevation: 1 yard longer for every yard uphill, 1 yard shorter for every yard downhill.
/// - Wind: a headwind adds 1% per mph, a tailwind takes off 0.5% per mph. Crosswind only counts
///   the part of the wind blowing along the shot.
/// - Temperature: 2 yards shorter for every 10°F below 75°F on a 150-yard shot (scaled by distance),
///   and the same longer above it.
enum PlaysLike {
    struct Result: Equatable {
        var yards: Int
        var elevationYards: Int
        var windYards: Int
        var temperatureYards: Int
    }

    static func yards(_ distance: Int,
                      shotBearing: Double,
                      rise meters: Double? = nil,
                      conditions: Conditions? = nil) -> Result {
        let base = Double(distance)
        let elevation = (meters ?? 0) / Geo.metersPerYard

        var wind = 0.0
        var temperature = 0.0
        if let conditions {
            // Wind blowing FROM the direction you face is a headwind.
            let angle = (conditions.windFromDegrees - shotBearing) * .pi / 180
            let headwind = conditions.windMph * cos(angle)
            wind = headwind >= 0 ? base * 0.01 * headwind : base * 0.005 * headwind
            temperature = (75 - conditions.temperatureF) / 10 * 2 * (base / 150)
        }
        let total = base + elevation + wind + temperature
        return Result(yards: Int(total.rounded()),
                      elevationYards: Int(elevation.rounded()),
                      windYards: Int(wind.rounded()),
                      temperatureYards: Int(temperature.rounded()))
    }

    /// Headwind (+) or tailwind (-) part of the wind, and the crosswind, in mph, for a shot direction.
    static func components(_ conditions: Conditions, shotBearing: Double) -> (head: Double, cross: Double) {
        let angle = (conditions.windFromDegrees - shotBearing) * .pi / 180
        return (conditions.windMph * cos(angle), conditions.windMph * sin(angle))
    }
}

/// The golfer's clubs and how far they carry each one. Starts from typical amateur numbers;
/// tracked shots can replace these later.
struct Bag: Codable, Hashable {
    struct Club: Codable, Hashable {
        var name: String
        var shortName: String
        var carryYards: Int
    }

    var clubs: [Club]

    static let standard = Bag(clubs: [
        Club(name: "Driver", shortName: "Dr", carryYards: 230),
        Club(name: "3 Wood", shortName: "3w", carryYards: 210),
        Club(name: "Hybrid", shortName: "Hy", carryYards: 190),
        Club(name: "5 Iron", shortName: "5i", carryYards: 175),
        Club(name: "6 Iron", shortName: "6i", carryYards: 165),
        Club(name: "7 Iron", shortName: "7i", carryYards: 155),
        Club(name: "8 Iron", shortName: "8i", carryYards: 145),
        Club(name: "9 Iron", shortName: "9i", carryYards: 135),
        Club(name: "Pitching Wedge", shortName: "PW", carryYards: 120),
        Club(name: "Gap Wedge", shortName: "GW", carryYards: 105),
        Club(name: "Sand Wedge", shortName: "SW", carryYards: 90),
        Club(name: "Lob Wedge", shortName: "LW", carryYards: 70),
    ])

    /// The shortest club that still carries the distance, or the longest club when nothing does.
    func club(for yards: Int) -> Club? {
        guard yards > 30 else { return nil }
        let byCarry = clubs.sorted { $0.carryYards < $1.carryYards }
        return byCarry.first { $0.carryYards >= yards } ?? byCarry.last
    }
}
