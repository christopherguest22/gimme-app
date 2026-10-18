import Foundation

/// Everything Gimme needs from a server. `MockBackend` runs fully offline for the prototype;
/// a `SupabaseBackend` implementing the same protocol plugs in next (see supabase/schema.sql).
protocol GimmeBackend {
    func currentUser() async throws -> Player
    func friends() async throws -> [Player]
    func feed() async throws -> [FeedPost]
    func publish(_ post: FeedPost) async throws
    func drops(for course: Course) async throws -> [Drop]
    /// The server re-checks everything: active round, inside the geofence, prize left,
    /// one claim per golfer, and the hole challenge if there is one.
    func claim(drop: Drop, round: Round, at point: Coordinate, holeStrokes: Int?) async throws -> WonPrize
    func save(_ round: Round) async throws
}

enum ClaimError: LocalizedError {
    case roundNotActive, outsideHole, soldOut, alreadyClaimed, challengeNotMet

    var errorDescription: String? {
        switch self {
        case .roundNotActive: "Drops only unlock during an active round."
        case .outsideHole: "You need to be on the hole to claim this drop."
        case .soldOut: "This drop is all gone."
        case .alreadyClaimed: "You already claimed this drop."
        case .challengeNotMet: "Challenge not met this time."
        }
    }
}

actor MockBackend: GimmeBackend {
    private let me = Player(id: "me", name: "You", avatar: "🏌️", handicap: nil)
    private var friendList = [
        Player(id: "jake", name: "Jake", avatar: "🧢", handicap: 8.4, playingNow: "Hole 6 at Pine Ridge"),
        Player(id: "maria", name: "Maria", avatar: "⛳️", handicap: 14.2),
        Player(id: "dev", name: "Dev", avatar: "🦅", handicap: 3.1, playingNow: "Hole 14 at Gimme Demo Links"),
        Player(id: "sam", name: "Sam", avatar: "🍺", handicap: 21.7),
    ]
    private var posts: [FeedPost] = []
    private var stock: [String: Int] = [:]
    private var claimed = Set<String>()
    private var rounds: [Round] = []

    init() {
        posts = [
            FeedPost(author: friendList[2], kind: .round, title: "Shot 71 at Gimme Demo Links",
                     detail: "-1 with 4 birdies. Putter was hot.", postedAt: .now.addingTimeInterval(-3_600), likes: 6),
            FeedPost(author: friendList[0], kind: .drop, title: "Won a sleeve of balls on 7",
                     detail: "Fairway Co. drop. Par or better and it's yours.", postedAt: .now.addingTimeInterval(-7_200), likes: 3),
            FeedPost(author: friendList[1], kind: .note, title: "Saturday 8:10am, who's in?",
                     detail: "Need a fourth.", postedAt: .now.addingTimeInterval(-86_400), likes: 2),
        ]
    }

    func currentUser() async throws -> Player { me }
    func friends() async throws -> [Player] { friendList }
    func feed() async throws -> [FeedPost] { posts.sorted { $0.postedAt > $1.postedAt } }
    func publish(_ post: FeedPost) async throws { posts.append(post) }
    func save(_ round: Round) async throws {
        rounds.removeAll { $0.id == round.id }
        rounds.append(round)
    }

    /// Sample sponsors on four holes of any course, ringed around each green.
    func drops(for course: Course) async throws -> [Drop] {
        let offers: [(hole: Int, brand: String, prize: String, detail: String, challenge: Drop.Challenge, count: Int)] = [
            (3, "Green Read Putters", "20% off any putter", "Online code, good for 30 days.", .none, 25),
            (7, "Fairway Co.", "Free sleeve of balls", "Pick up at the pro shop.", .parOrBetter, 12),
            (12, "Back Nine Apparel", "Free logo hat", "Shipped to you.", .birdieOrBetter, 5),
            (16, "Nineteenth Hole Brewing", "Free drink at the turn", "Show the code at the bar.", .none, 40),
        ]
        return offers.compactMap { offer in
            guard let hole = course.hole(offer.hole) else { return nil }
            let id = "\(course.id)-\(offer.hole)"
            return Drop(id: id, brand: offer.brand, prize: offer.prize, detail: offer.detail,
                        courseId: course.id, holeNumber: offer.hole, center: hole.greenCenter,
                        radiusMeters: 45, challenge: offer.challenge,
                        remaining: stock[id] ?? offer.count,
                        expires: Calendar.current.date(byAdding: .day, value: 7, to: .now)!)
        }
    }

    func claim(drop: Drop, round: Round, at point: Coordinate, holeStrokes: Int?) async throws -> WonPrize {
        guard round.isActive, round.courseId == drop.courseId else { throw ClaimError.roundNotActive }
        guard drop.contains(point) else { throw ClaimError.outsideHole }
        guard !claimed.contains(drop.id) else { throw ClaimError.alreadyClaimed }
        let left = stock[drop.id] ?? drop.remaining
        guard left > 0 else { throw ClaimError.soldOut }
        if drop.challenge != .none {
            guard let holeStrokes, drop.challenge.isMet(strokes: holeStrokes, par: round.pars[drop.holeNumber - 1]) else {
                throw ClaimError.challengeNotMet
            }
        }
        stock[drop.id] = left - 1
        claimed.insert(drop.id)
        var won = drop
        won.remaining = left - 1
        let code = "GIMME-" + String(UUID().uuidString.prefix(6))
        return WonPrize(drop: won, code: code)
    }
}
