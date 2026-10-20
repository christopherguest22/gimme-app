import Foundation

enum Scoring {
    static func formatToPar(_ value: Int) -> String {
        value == 0 ? "E" : value > 0 ? "+\(value)" : "\(value)"
    }

    /// Name for a hole score relative to par (Birdie, Bogey, ...).
    static func label(strokes: Int, par: Int) -> String {
        if strokes == 1 { return "Ace" }
        switch strokes - par {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double"
        default: return "+\(strokes - par)"
        }
    }

    /// Simplified World Handicap System estimate from complete 18-hole rounds.
    /// Uses course rating = par and slope 113 until real ratings come from course data,
    /// caps each hole at net double bogey (without strokes), and averages the best differentials.
    static func handicapEstimate(rounds: [Round], playerId: String) -> Double? {
        let differentials = rounds
            .filter { $0.pars.count == 18 && $0.holesPlayed(playerId) == 18 }
            .sorted { $0.date > $1.date }
            .prefix(20)
            .map { round -> Double in
                let adjusted = zip(round.scores[playerId] ?? [], round.pars).reduce(0) { sum, pair in
                    sum + min(pair.0 ?? pair.1, pair.1 + 2)
                }
                let rating = Double(round.pars.reduce(0, +))
                let slope = 113.0
                return (Double(adjusted) - rating) * 113 / slope
            }
        guard differentials.count >= 3 else { return nil }
        let count: Int
        switch differentials.count {
        case 3...5: count = 1
        case 6...8: count = 2
        case 9...11: count = 3
        case 12...14: count = 4
        case 15...16: count = 5
        case 17...18: count = 6
        case 19: count = 7
        default: count = 8
        }
        let best = differentials.sorted().prefix(count)
        let index = best.reduce(0, +) / Double(best.count)
        return (index * 10).rounded() / 10
    }

    // MARK: Side games (gross, no handicap strokes yet)

    struct SkinsResult: Equatable {
        /// Player id that won each decided hole.
        var winners: [Int: String] = [:]
        var skins: [String: Int] = [:]
        /// Skins riding on the next hole after ties.
        var carryover = 0
    }

    /// Skins: lowest score alone on a hole wins it; ties carry the skin to the next hole.
    static func skins(_ round: Round) -> SkinsResult {
        var result = SkinsResult()
        var pot = 1
        for hole in 1...round.pars.count {
            let scores = round.players.compactMap { p in round.strokes(p.id, hole: hole).map { (p.id, $0) } }
            guard scores.count == round.players.count, let best = scores.map(\.1).min() else { break }
            let leaders = scores.filter { $0.1 == best }
            if leaders.count == 1 {
                result.winners[hole] = leaders[0].0
                result.skins[leaders[0].0, default: 0] += pot
                pot = 1
            } else {
                pot += 1
            }
        }
        result.carryover = pot - 1
        return result
    }

    struct NassauLeg: Identifiable, Equatable {
        var name: String
        /// Leader's player id, nil when tied or not started.
        var leader: String?
        var margin: Int
        var holesCounted: Int
        var id: String { name }

        /// A leg pays out once every hole in it has a score from everyone.
        func isFinished(holes total: Int) -> Bool {
            holesCounted > 0 && holesCounted == (name == "Overall" ? total : 9)
        }
    }

    /// Nassau as stroke play: lowest total on the front nine, back nine and full 18,
    /// counting only holes everyone has finished.
    static func nassau(_ round: Round) -> [NassauLeg] {
        let count = round.pars.count
        let legs: [(String, ClosedRange<Int>)] = count >= 18
            ? [("Front 9", 1...9), ("Back 9", 10...18), ("Overall", 1...18)]
            : [("Overall", 1...count)]
        return legs.map { (name, holes) -> NassauLeg in
            let done = holes.filter { h in round.players.allSatisfy { round.strokes($0.id, hole: h) != nil } }
            let totals = round.players.map { p in (p.id, done.reduce(0) { $0 + (round.strokes(p.id, hole: $1) ?? 0) }) }
                .sorted { $0.1 < $1.1 }
            guard !done.isEmpty, totals.count > 1 else {
                return NassauLeg(name: name, leader: nil, margin: 0, holesCounted: done.count)
            }
            let margin = totals[1].1 - totals[0].1
            return NassauLeg(name: name, leader: margin > 0 ? totals[0].0 : nil, margin: margin, holesCounted: done.count)
        }
    }
}
