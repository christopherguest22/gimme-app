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
}
