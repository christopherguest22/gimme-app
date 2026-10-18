import Foundation

struct Course: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var holes: [Hole]
    /// Where the data came from, shown as attribution (OpenStreetMap requires it).
    var source: String

    var par: Int { holes.map(\.par).reduce(0, +) }

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

    var id: Int { number }
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

/// A course near the golfer, before its holes are loaded.
struct CourseSummary: Identifiable, Hashable {
    var id: String
    var name: String
    var center: Coordinate
}
