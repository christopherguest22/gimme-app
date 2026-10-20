import Foundation

struct Player: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var avatar: String
    var handicap: Double?
    /// Set for friends who are on a course right now.
    var playingNow: String?
    /// Where friends can pay this golfer for side games.
    var venmo: String? = nil
    var cashApp: String? = nil
    /// The course they call home, shown on their posts the way LinkedIn shows a job title.
    var homeCourse: String? = nil
    /// What friends type to add them.
    var handle: String? = nil
    /// Set while they are streaming a round, so friends can tap in and watch.
    var liveRoundId: UUID? = nil

    /// One line under their name: "8.4 HCP · Turtle Point".
    var headline: String {
        [handicap.map { String(format: "%.1f HCP", $0) }, homeCourse].compactMap { $0 }.joined(separator: " · ")
    }
}

struct Round: Identifiable, Codable, Hashable {
    var id = UUID()
    var courseId: String
    var courseName: String
    var date = Date()
    var players: [Player]
    var pars: [Int]
    /// Strokes per player id, indexed by hole number - 1. nil means not entered yet.
    var scores: [String: [Int?]]
    var isActive = true
    /// Dollar stakes for skins and Nassau; nil when the group plays for fun.
    var stakes: Stakes? = nil
    /// Settle-up payments (`Payment.id`) that have been marked as paid.
    var paid: [String]? = nil

    init(course: Course, players: [Player]) {
        courseId = course.id
        courseName = course.name
        self.players = players
        pars = course.holes.sorted { $0.number < $1.number }.map(\.par)
        scores = Dictionary(uniqueKeysWithValues: players.map { ($0.id, Array(repeating: nil, count: course.holes.count)) })
    }

    func strokes(_ playerId: String, hole: Int) -> Int? {
        guard let card = scores[playerId], card.indices.contains(hole - 1) else { return nil }
        return card[hole - 1]
    }

    mutating func setStrokes(_ strokes: Int?, for playerId: String, hole: Int) {
        guard scores[playerId]?.indices.contains(hole - 1) == true else { return }
        scores[playerId]?[hole - 1] = strokes
    }

    func total(_ playerId: String) -> Int {
        (scores[playerId] ?? []).compactMap { $0 }.reduce(0, +)
    }

    func holesPlayed(_ playerId: String) -> Int {
        (scores[playerId] ?? []).compactMap { $0 }.count
    }

    /// Score relative to par over the holes this player has finished.
    func toPar(_ playerId: String) -> Int {
        let card = scores[playerId] ?? []
        return zip(card, pars).reduce(0) { sum, pair in
            guard let strokes = pair.0 else { return sum }
            return sum + strokes - pair.1
        }
    }

    var isComplete: Bool {
        players.allSatisfy { holesPlayed($0.id) == pars.count }
    }

    /// Leaderboard order: lowest to par first.
    var standings: [Player] {
        players.sorted { toPar($0.id) < toPar($1.id) }
    }

    var shareText: String {
        var lines = ["⛳️ \(courseName), \(date.formatted(date: .abbreviated, time: .omitted))"]
        for p in standings {
            lines.append("\(p.name): \(total(p.id)) (\(Scoring.formatToPar(toPar(p.id))) thru \(holesPlayed(p.id)))")
        }
        lines.append("Scored with Gimme")
        return lines.joined(separator: "\n")
    }
}

struct ChatMessage: Identifiable, Codable, Hashable {
    var id = UUID()
    var author: Player
    var text: String
    var sentAt = Date()
}

