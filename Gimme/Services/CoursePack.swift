import Foundation

/// Courses that ship inside the app for the launch area, so they show up first in the course
/// list with their full scorecard even before the network answers. Hole positions still come
/// from OpenStreetMap on the phone (or from holes the golfer maps in the app).
///
/// Launch area: Kiawah Island, SC. Data lives in `Resources/kiawah-courses.json`.
struct PackCourse: Decodable, Identifiable, Hashable {
    struct PackTee: Decodable, Hashable {
        var name: String
        var rating: Double
        var slope: Int
        var par: Int
        var yardage: Int
    }
    struct PackHole: Decodable, Hashable {
        var number: Int
        var par: Int
        var handicap: Int
        var yardages: [String: Int]
    }

    var slug: String
    var name: String
    /// The name OpenStreetMap uses, matched when finding the hole map.
    var osmName: String
    var ogaId: String
    var lat: Double
    var lng: Double
    var membersOnly: Bool
    var featured: Bool
    var tees: [PackTee]
    var holes: [PackHole]

    var id: String { "pack/\(slug)" }
    var center: Coordinate { Coordinate(lat, lng) }
    var summary: CourseSummary { CourseSummary(id: id, name: name, center: center) }
    var longestTee: PackTee? { tees.max { $0.yardage < $1.yardage } }

    var scorecard: ScorecardService.Scorecard {
        .init(name: name,
              tees: tees.map { TeeSet(name: $0.name, rating: $0.rating, slope: $0.slope, par: $0.par, yardage: $0.yardage) },
              holes: holes.map { .init(number: $0.number, par: $0.par, handicap: $0.handicap, yardages: $0.yardages) })
    }
}

enum CoursePack {
    private struct File: Decodable {
        var area: String
        var courses: [PackCourse]
    }

    private static let file: File? = {
        guard let url = Bundle.main.url(forResource: "kiawah-courses", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(File.self, from: data)
    }()

    static var area: String { file?.area ?? "" }
    /// Featured course first, then the rest in the order of the file.
    static var courses: [PackCourse] { (file?.courses ?? []).sorted { $0.featured && !$1.featured } }
    static var featured: PackCourse? { courses.first { $0.featured } }

    static func course(id: String) -> PackCourse? { courses.first { $0.id == id } }
}

/// Tee and green spots a golfer set on the course with Tools › "Set tee/green here".
/// Used where OpenStreetMap has no hole map yet, and to correct one that's off. Saved on the phone.
enum HoleOverrides {
    struct Spot: Codable, Hashable {
        var tee: Coordinate?
        var green: Coordinate?
    }

    private static func key(_ courseId: String) -> String { "holeOverrides.\(courseId)" }

    static func load(_ courseId: String) -> [Int: Spot] {
        guard let data = UserDefaults.standard.data(forKey: key(courseId)),
              let spots = try? JSONDecoder().decode([Int: Spot].self, from: data) else { return [:] }
        return spots
    }

    static func save(_ spot: Spot, hole: Int, courseId: String) {
        var spots = load(courseId)
        spots[hole] = spot
        if let data = try? JSONEncoder().encode(spots) {
            UserDefaults.standard.set(data, forKey: key(courseId))
        }
    }

    /// Moves tees and greens to the saved spots. Front and back of the green are put
    /// 14 m either side of the center along the line of play.
    static func apply(to course: Course) -> Course {
        var course = course
        let spots = load(course.id)
        for i in course.holes.indices {
            guard let spot = spots[course.holes[i].number] else { continue }
            if let tee = spot.tee { course.holes[i].tee = tee }
            if let green = spot.green {
                course.holes[i].greenCenter = green
                let bearing = Geo.bearing(from: course.holes[i].tee, to: green)
                course.holes[i].greenFront = Geo.offset(green, meters: -14, bearing: bearing)
                course.holes[i].greenBack = Geo.offset(green, meters: 14, bearing: bearing)
            }
        }
        return course
    }
}
