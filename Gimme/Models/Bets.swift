import Foundation

/// Dollar amounts the group plays the side games for. Zero means that game isn't for money.
struct Stakes: Codable, Hashable {
    /// Each other player pays the winner this much per skin.
    var perSkin: Double = 0
    /// Each other player pays the leader of a finished Nassau leg (front 9, back 9, overall) this much.
    var perNassauLeg: Double = 0

    var isOn: Bool { perSkin > 0 || perNassauLeg > 0 }
}

/// One person paying another to settle the round.
struct Payment: Identifiable, Hashable {
    var from: String
    var to: String
    var amount: Double
    var id: String { "\(from)>\(to)" }
}

/// Works out who owes whom from the side games. Gimme never holds the money: golfers settle with
/// each other in Venmo or Cash App, and mark each payment as paid here.
enum Settlement {
    /// What each player is up (+) or down (-) across skins and Nassau. Always sums to zero.
    static func balances(_ round: Round, stakes: Stakes) -> [String: Double] {
        let ids = round.players.map(\.id)
        var balance = Dictionary(uniqueKeysWithValues: ids.map { ($0, 0.0) })
        let others = Double(max(ids.count - 1, 0))

        // Skins: the winner of each decided skin collects the stake from every other player.
        if stakes.perSkin > 0 {
            for (winner, count) in Scoring.skins(round).skins {
                let skins = Double(count)
                for id in ids {
                    if id == winner {
                        balance[id, default: 0] += stakes.perSkin * skins * others
                    } else {
                        balance[id, default: 0] -= stakes.perSkin * skins
                    }
                }
            }
        }

        // Nassau: only finished legs pay, and a tied leg pays nobody.
        if stakes.perNassauLeg > 0 {
            for leg in Scoring.nassau(round) where leg.isFinished(holes: round.pars.count) {
                guard let leader = leg.leader else { continue }
                for id in ids {
                    balance[id, default: 0] += id == leader ? stakes.perNassauLeg * others : -stakes.perNassauLeg
                }
            }
        }
        return balance
    }

    /// The fewest payments that settle everyone: biggest loser pays biggest winner first.
    static func payments(_ balances: [String: Double]) -> [Payment] {
        var owes = balances.filter { $0.value < -0.005 }.map { ($0.key, -$0.value) }.sorted { $0.1 > $1.1 }
        var gets = balances.filter { $0.value > 0.005 }.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
        var result: [Payment] = []
        var i = 0, j = 0
        while i < owes.count, j < gets.count {
            let amount = min(owes[i].1, gets[j].1)
            result.append(Payment(from: owes[i].0, to: gets[j].0, amount: (amount * 100).rounded() / 100))
            owes[i].1 -= amount
            gets[j].1 -= amount
            if owes[i].1 < 0.005 { i += 1 }
            if gets[j].1 < 0.005 { j += 1 }
        }
        return result
    }

    static func payments(_ round: Round) -> [Payment] {
        guard let stakes = round.stakes, stakes.isOn else { return [] }
        return payments(balances(round, stakes: stakes))
    }

    static func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "USD").precision(.fractionLength(amount.rounded() == amount ? 0 : 2)))
    }
}

/// Links that open Venmo or Cash App with the payment filled in. The golfer confirms it there.
enum PayLinks {
    static func venmo(handle: String, amount: Double, note: String, request: Bool = false) -> URL? {
        let user = handle.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
        guard !user.isEmpty else { return nil }
        var parts = URLComponents(string: "https://venmo.com/\(user)")
        parts?.queryItems = [
            URLQueryItem(name: "txn", value: request ? "charge" : "pay"),
            URLQueryItem(name: "amount", value: String(format: "%.2f", amount)),
            URLQueryItem(name: "note", value: note),
        ]
        return parts?.url
    }

    static func cashApp(cashtag: String, amount: Double) -> URL? {
        let tag = cashtag.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
        guard !tag.isEmpty else { return nil }
        return URL(string: "https://cash.app/$\(tag)/\(String(format: "%.2f", amount))")
    }
}
