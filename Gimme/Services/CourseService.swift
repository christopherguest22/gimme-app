import Foundation

/// Loads real course maps from OpenStreetMap through the free Overpass API.
/// Coverage depends on volunteers having mapped the course's holes (`golf=hole` lines),
/// greens, bunkers and water. Swap this type for a licensed provider (iGolf, Golfbert,
/// GolfAPI.io) when you need every course.
struct CourseService {
    var endpoint = URL(string: "https://overpass-api.de/api/interpreter")!

    enum CourseError: LocalizedError {
        case noHoles
        var errorDescription: String? { "This course has no mapped holes on OpenStreetMap yet." }
    }

    /// Golf courses within `radiusMeters` of the golfer.
    func nearbyCourses(around point: Coordinate, radiusMeters: Int = 25_000) async throws -> [CourseSummary] {
        let query = """
        [out:json][timeout:25];
        (way["leisure"="golf_course"](around:\(radiusMeters),\(point.latitude),\(point.longitude));
         relation["leisure"="golf_course"](around:\(radiusMeters),\(point.latitude),\(point.longitude)););
        out tags center;
        """
        let response = try await run(query)
        return response.elements.compactMap { element in
            guard let name = element.tags?["name"], let center = element.center else { return nil }
            return CourseSummary(id: "\(element.type)/\(element.id)", name: name, center: Coordinate(center.lat, center.lon))
        }
        .sorted { Geo.meters($0.center, point) < Geo.meters($1.center, point) }
    }

    /// Full hole-by-hole map for one course from `nearbyCourses`.
    func loadCourse(_ summary: CourseSummary) async throws -> Course {
        // Overpass areas are numbered from the OSM id: ways + 2.4 billion, relations + 3.6 billion.
        let parts = summary.id.split(separator: "/")
        guard parts.count == 2, let osmId = Int(parts[1]) else { throw CourseError.noHoles }
        let areaId = osmId + (parts[0] == "relation" ? 3_600_000_000 : 2_400_000_000)
        let query = """
        [out:json][timeout:25];
        area(id:\(areaId))->.course;
        (way["golf"](area.course); way["natural"="water"](area.course););
        out tags geom;
        """
        let response = try await run(query)
        let course = Self.parse(response.elements, id: summary.id, name: summary.name)
        guard !course.holes.isEmpty else { throw CourseError.noHoles }
        return course
    }

    private func run(_ query: String) async throws -> OverpassResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.httpBody = "data=\(query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")".data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(OverpassResponse.self, from: data)
    }

    /// Turns OSM golf features into holes. Each `golf=hole` line runs tee to green; the nearest
    /// green polygon gives front/middle/back measured along the line of play.
    static func parse(_ elements: [OverpassElement], id: String, name: String) -> Course {
        func shape(_ e: OverpassElement) -> [Coordinate] { (e.geometry ?? []).map { Coordinate($0.lat, $0.lon) } }

        let holeLines = elements.filter { $0.tags?["golf"] == "hole" }
        let greens = elements.filter { $0.tags?["golf"] == "green" }.map(shape)
        let bunkers = elements.filter { $0.tags?["golf"] == "bunker" }.map { ($0.id, Hazard.Kind.bunker, shape($0)) }
        let water = elements.filter {
            $0.tags?["golf"] == "water_hazard" || $0.tags?["golf"] == "lateral_water_hazard" || $0.tags?["natural"] == "water"
        }.map { ($0.id, Hazard.Kind.water, shape($0)) }

        var holes: [Hole] = []
        for line in holeLines {
            let path = shape(line)
            guard let tee = path.first, let end = path.last, path.count >= 2,
                  let number = line.tags?["ref"].flatMap({ Int($0) }) else { continue }
            let par = line.tags?["par"].flatMap { Int($0) } ?? 4
            let lastLeg = path[path.count - 2]

            // Green: the polygon whose middle is closest to the end of the hole line.
            let green = greens.min { a, b in
                Geo.meters(Geo.centroid(a) ?? end, end) < Geo.meters(Geo.centroid(b) ?? end, end)
            }
            var front = end, center = end, back = end
            if let green, let middle = Geo.centroid(green), Geo.meters(middle, end) < 60 {
                center = middle
                front = green.min { Geo.along($0, from: lastLeg, toward: end) < Geo.along($1, from: lastLeg, toward: end) } ?? middle
                back = green.max { Geo.along($0, from: lastLeg, toward: end) < Geo.along($1, from: lastLeg, toward: end) } ?? middle
            }

            // Hazards: anything within 40 m of the line of play, measured near and far edge from the tee.
            let hazards = (bunkers + water).compactMap { (osmId, kind, outline) -> Hazard? in
                guard !outline.isEmpty else { return nil }
                let close = zip(path, path.dropFirst()).contains { a, b in
                    outline.contains { Geo.distanceToSegment($0, a, b) < 40 }
                }
                guard close,
                      let near = outline.min(by: { Geo.meters(tee, $0) < Geo.meters(tee, $1) }),
                      let far = outline.max(by: { Geo.meters(tee, $0) < Geo.meters(tee, $1) }) else { return nil }
                return Hazard(id: "\(number)-\(osmId)", kind: kind, near: near, carry: far)
            }

            holes.append(Hole(number: number, par: par, tee: tee,
                              greenFront: front, greenCenter: center, greenBack: back,
                              hazards: hazards))
        }
        // Courses with several loops can reuse hole refs; keep the first of each number.
        var seen = Set<Int>()
        holes = holes.sorted { $0.number < $1.number }.filter { seen.insert($0.number).inserted }
        return Course(id: id, name: name, holes: holes, source: "© OpenStreetMap contributors")
    }
}

struct OverpassResponse: Decodable {
    var elements: [OverpassElement]
}

struct OverpassElement: Decodable {
    struct Point: Decodable { var lat: Double; var lon: Double }

    var type: String
    var id: Int
    var tags: [String: String]?
    var center: Point?
    var geometry: [Point]?
}
