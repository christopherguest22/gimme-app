import Foundation

/// Hole-by-hole scorecards (par, stroke index, yardage for every tee, course rating and slope)
/// from OpenGolfAPI. Course data reads are free with no key; the data is ODbL licensed like
/// OpenStreetMap, so the app shows attribution. US courses only for now.
///
/// The OpenStreetMap map gives the shape of each hole; this adds the numbers printed on the card.
struct ScorecardService {
    var baseURL = URL(string: "https://api.opengolfapi.org/api/v1")!

    struct Scorecard: Equatable {
        struct HoleCard: Equatable {
            var number: Int
            var par: Int?
            var handicap: Int?
            var yardages: [String: Int]
            var tee: Coordinate?
            var greenFront: Coordinate?
            var greenCenter: Coordinate?
            var greenBack: Coordinate?
        }
        var name: String
        var tees: [TeeSet]
        var holes: [HoleCard]
    }

    /// Finds the course on OpenGolfAPI by name and location, then loads its scorecard.
    func scorecard(named name: String, near point: Coordinate) async throws -> Scorecard? {
        var search = URLComponents(url: baseURL.appendingPathComponent("courses/search"), resolvingAgainstBaseURL: false)!
        search.queryItems = [URLQueryItem(name: "q", value: name)]
        let (data, _) = try await URLSession.shared.data(from: search.url!)
        guard let id = Self.bestMatch(in: data, near: point) else { return nil }
        let (detail, _) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("courses/\(id)"))
        return Self.parse(detail)
    }

    /// The search result closest to the course, if one is within 3 km.
    static func bestMatch(in data: Data, near point: Coordinate) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let courses = json["courses"] as? [[String: Any]] else { return nil }
        return courses
            .compactMap { c -> (String, Double)? in
                guard let id = c["id"] as? String, let at = coordinate(c) else { return nil }
                return (id, Geo.meters(at, point))
            }
            .filter { $0.1 < 3_000 }
            .min { $0.1 < $1.1 }?.0
    }

    static func parse(_ data: Data) -> Scorecard? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let name = json["course_name"] as? String ?? ""

        let tees = (json["tees"] as? [[String: Any]] ?? []).compactMap { t -> TeeSet? in
            guard let name = t["tee_name"] as? String, let yards = int(t["yardage"]) else { return nil }
            return TeeSet(name: name, color: t["tee_color"] as? String,
                          rating: t["course_rating"] as? Double ?? int(t["course_rating"]).map(Double.init),
                          slope: int(t["slope"]), par: int(t["par"]), yardage: yards)
        }

        let holes = (json["holes_data"] as? [[String: Any]] ?? []).compactMap { h -> Scorecard.HoleCard? in
            guard let number = int(h["number"]) else { return nil }
            var yardages: [String: Int] = [:]
            for (key, value) in h["yardages"] as? [String: Any] ?? [:] where key != "web" {
                if let yards = int(value) { yardages[key.capitalized] = yards }
            }
            let green = h["green"] as? [String: Any]
            return Scorecard.HoleCard(number: number,
                                      par: int(h["par"]),
                                      handicap: int(h["handicap_index"]),
                                      yardages: yardages,
                                      tee: coordinate(h["tee_coords"]),
                                      greenFront: coordinate(green?["front"]),
                                      greenCenter: coordinate(green?["center"]),
                                      greenBack: coordinate(green?["back"]))
        }
        return Scorecard(name: name, tees: tees, holes: holes)
    }

    /// Adds the scorecard to a mapped course. Where OpenStreetMap has no holes but the scorecard
    /// has tee and green positions, the holes are built from the scorecard instead.
    static func merge(_ card: Scorecard, into course: Course) -> Course {
        var course = course
        course.tees = card.tees
        if course.holes.isEmpty {
            course.holes = card.holes.compactMap { h in
                guard let tee = h.tee, let center = h.greenCenter else { return nil }
                return Hole(number: h.number, par: h.par ?? 4, tee: tee,
                            greenFront: h.greenFront ?? center, greenCenter: center, greenBack: h.greenBack ?? center,
                            handicap: h.handicap, yardages: h.yardages)
            }
        } else {
            for i in course.holes.indices {
                guard let h = card.holes.first(where: { $0.number == course.holes[i].number }) else { continue }
                if let par = h.par { course.holes[i].par = par }
                course.holes[i].handicap = h.handicap
                course.holes[i].yardages = h.yardages.isEmpty ? nil : h.yardages
            }
        }
        course.source += " · Scorecard © OpenGolfAPI (ODbL)"
        return course
    }

    // MARK: Lenient JSON helpers (fields are sometimes numbers, strings or null)

    static func int(_ value: Any?) -> Int? {
        switch value {
        case let n as Int: n
        case let d as Double: Int(d.rounded())
        case let s as String: Int(s)
        default: nil
        }
    }

    /// Accepts {"lat","lng"}, {"lat","lon"}, {"latitude","longitude"} or a GeoJSON [lng, lat] pair.
    static func coordinate(_ value: Any?) -> Coordinate? {
        if let pair = value as? [Double], pair.count >= 2 { return Coordinate(pair[1], pair[0]) }
        guard let d = value as? [String: Any] else { return nil }
        let lat = d["lat"] ?? d["latitude"]
        let lng = d["lng"] ?? d["lon"] ?? d["longitude"]
        guard let lat = lat as? Double ?? int(lat).map(Double.init),
              let lng = lng as? Double ?? int(lng).map(Double.init) else { return nil }
        return Coordinate(lat, lng)
    }
}
