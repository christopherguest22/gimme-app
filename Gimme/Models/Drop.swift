import Foundation

/// A brand prize placed on a hole. Unlocks when a golfer in an active round is inside the geofence.
struct Drop: Identifiable, Codable, Hashable {
    enum Challenge: String, Codable {
        case none, parOrBetter, birdieOrBetter

        var label: String {
            switch self {
            case .none: "Unlocks when you reach the green"
            case .parOrBetter: "Make par or better to win"
            case .birdieOrBetter: "Make birdie or better to win"
            }
        }

        func isMet(strokes: Int, par: Int) -> Bool {
            switch self {
            case .none: true
            case .parOrBetter: strokes <= par
            case .birdieOrBetter: strokes < par
            }
        }
    }

    var id: String
    var brand: String
    var prize: String
    var detail: String
    var courseId: String
    var holeNumber: Int
    var center: Coordinate
    var radiusMeters: Double
    var challenge: Challenge
    var remaining: Int
    var expires: Date

    func contains(_ point: Coordinate) -> Bool {
        Geo.meters(center, point) <= radiusMeters
    }
}

struct WonPrize: Identifiable, Codable, Hashable {
    var id = UUID()
    var drop: Drop
    var code: String
    var wonAt = Date()
    var redeemed = false
}
