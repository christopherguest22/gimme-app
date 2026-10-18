import Foundation

struct Course: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var holes: [Hole]
    /// Where the data came from, shown as attribution (OpenStreetMap requires it).
    var source: String
    /// Tee boxes from the course scorecard (OpenGolfAPI). nil until the scorecard is loaded.
    var tees: [TeeSet]? = nil

    var par: Int { holes.map(\.par).reduce(0, +) }

    /// Tees with yardages on the holes, longest first, so the picker reads like a scorecard.
    var teeNames: [String] {
        if let tees, !tees.isEmpty {
            var seen = Set<String>()
            return tees.sorted { $0.yardage > $1.yardage }.map(\.name).filter { seen.insert($0).inserted }
        }
        let names = Set(holes.flatMap { ($0.yardages ?? [:]).keys })
        return names.sorted { a, b in total(a) > total(b) }
    }

    func total(_ tee: String) -> Int { holes.compactMap { $0.yardage(tee) }.reduce(0, +) }

    func hole(_ number: Int) -> Hole? { holes.first { $0.number == number } }
}

struct Hole: Identifiable, Codable, Hashable {
    var number: Int
    var par: Int
    var tee: Coordinate
    var greenFront: Coordinate
    var greenCenter: Coordinate
    var greenBack: Coordinate
    var hazards: [Hazard] = []
    /// Stroke index from the scorecard: 1 is the hardest hole.
    var handicap: Int? = nil
    /// Scorecard yardage per tee name ("Blue": 411).
    var yardages: [String: Int]? = nil
    /// Ground height in meters above sea level, for plays-like distances.
    var teeElevation: Double? = nil
    var greenElevation: Double? = nil

    var id: Int { number }

    /// Scorecard yardage for a tee, matched without caring about case.
    func yardage(_ tee: String?) -> Int? {
        guard let tee, let yardages else { return nil }
        return yardages.first { $0.key.caseInsensitiveCompare(tee) == .orderedSame }?.value
    }
    var bearing: Double { Geo.bearing(from: tee, to: greenCenter) }
    var lengthYards: Int { Geo.yards(tee, greenCenter) }
}

struct Hazard: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case bunker, water }

    var id: String
    var kind: Kind
    /// The edge closest to the tee: distance to reach it.
    var near: Coordinate
    /// The far edge: distance to carry it.
    var carry: Coordinate

    var label: String { kind == .water ? "Water" : "Bunker" }
}

/// One set of tee boxes, as printed on the scorecard.
struct TeeSet: Codable, Hashable, Identifiable {
    var name: String
    var color: String?
    var rating: Double?
    var slope: Int?
    var par: Int?
    var yardage: Int
    var id: String { name }
}

/// A course near the golfer, before its holes are loaded.
struct CourseSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var center: Coordinate
}
