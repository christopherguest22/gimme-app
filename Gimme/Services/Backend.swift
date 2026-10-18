import Foundation

/// Live changes to a round from other phones in the group.
enum RoundEvent {
    case score(playerId: String, hole: Int, strokes: Int?)
    case chat(ChatMessage)
}

/// Everything Gimme needs from a server. `MockBackend` runs fully offline with sample data;
/// `SupabaseBackend` talks to the real database (see supabase/schema.sql).
protocol GimmeBackend {
    // Account
    /// The signed-in golfer, or nil when nobody is signed in.
    func currentUser() async throws -> Player?
    func sendSignInCode(email: String) async throws
    func verifySignInCode(email: String, code: String) async throws -> Player
    func updateProfile(name: String, avatar: String) async throws -> Player
    func signOut() async throws

    // Friends and feed
    func friends() async throws -> [Player]
    func addFriend(handle: String) async throws
    func feed() async throws -> [FeedPost]
    func publish(_ post: FeedPost) async throws

    // Rounds
    func startRound(_ round: Round, course: Course) async throws -> Round
    func saveScore(round: Round, playerId: String, hole: Int, strokes: Int?) async throws
    func sendChat(_ message: ChatMessage, round: Round) async throws
    func roundEvents(_ round: Round) -> AsyncStream<RoundEvent>
    func finish(_ round: Round) async throws
    func pastRounds() async throws -> [Round]

    // Drops
    func drops(for course: Course) async throws -> [Drop]
    /// Records that the golfer is inside the drop's geofence during an active round.
    /// The server re-checks the position, the round and the dates.
    func visit(drop: Drop, round: Round, at point: Coordinate) async throws
    /// The server checks the visit, stock left, one claim per golfer and the hole challenge.
    func claim(drop: Drop, round: Round) async throws -> WonPrize
    func wallet() async throws -> [WonPrize]
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

/// Offline backend with sample friends and sponsors. Friends in your group "play along":
/// their scores arrive a little after yours, so the live scorecard can be tried solo.
actor MockBackend: GimmeBackend {
    private var me: Player?
    private var friendList = [
        Player(id: "jake", name: "Jake", avatar: "🧢", handicap: 8.4, playingNow: "Hole 6 at Pine Ridge"),
        Player(id: "maria", name: "Maria", avatar: "⛳️", handicap: 14.2),
        Player(id: "dev", name: "Dev", avatar: "🦅", handicap: 3.1, playingNow: "Hole 14 at Gimme Demo Links"),
        Player(id: "sam", name: "Sam", avatar: "🍺", handicap: 21.7),
    ]
    private var posts: [FeedPost] = []
    private var stock: [String: Int] = [:]
    private var visits = Set<String>()
    private var prizes: [WonPrize] = []
    private var rounds: [UUID: Round] = [:]
    private var listeners: [UUID: AsyncStream<RoundEvent>.Continuation] = [:]

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

    // MARK: Account

    func currentUser() async throws -> Player? { me }

    func sendSignInCode(email: String) async throws {}

    func verifySignInCode(email: String, code: String) async throws -> Player {
        let player = Player(id: "me", name: email.components(separatedBy: "@").first ?? "You", avatar: "🏌️")
        me = player
        return player
    }

    func updateProfile(name: String, avatar: String) async throws -> Player {
        let player = Player(id: "me", name: name, avatar: avatar)
        me = player
        return player
    }

    func signOut() async throws { me = nil }

    // MARK: Friends and feed

    func friends() async throws -> [Player] { friendList }

    func addFriend(handle: String) async throws {
        let name = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).capitalized
        guard !name.isEmpty, !friendList.contains(where: { $0.name == name }) else { return }
        friendList.append(Player(id: name.lowercased(), name: name, avatar: "🙂"))
    }

    func feed() async throws -> [FeedPost] { posts.sorted { $0.postedAt > $1.postedAt } }
    func publish(_ post: FeedPost) async throws { posts.append(post) }

    // MARK: Rounds

    func startRound(_ round: Round, course: Course) async throws -> Round {
        rounds[round.id] = round
        return round
    }

    func saveScore(round: Round, playerId: String, hole: Int, strokes: Int?) async throws {
        rounds[round.id]?.setStrokes(strokes, for: playerId, hole: hole)
        guard playerId == "me", strokes != nil, let saved = rounds[round.id] else { return }
        // Friends finish the same hole a few seconds after you.
        for friend in saved.players where friend.id != "me" && saved.strokes(friend.id, hole: hole) == nil {
            let par = saved.pars[hole - 1]
            let skill = friend.handicap ?? 18
            let roll = Double.random(in: 0...1)
            let parChance: Double = 0.25 + (36 - skill) / 60
            var strokes = par + 2
            if roll < 0.12 {
                strokes = par - 1
            } else if roll < parChance {
                strokes = par
            } else if roll < 0.85 {
                strokes = par + 1
            }
            let delay = UInt64.random(in: 2...8) * 1_000_000_000
            let id = round.id, friendId = friend.id, score = strokes
            Task {
                try? await Task.sleep(nanoseconds: delay)
                await self.friendScored(roundId: id, playerId: friendId, hole: hole, strokes: score)
            }
        }
    }

    private func friendScored(roundId: UUID, playerId: String, hole: Int, strokes: Int) {
        rounds[roundId]?.setStrokes(strokes, for: playerId, hole: hole)
        listeners[roundId]?.yield(.score(playerId: playerId, hole: hole, strokes: strokes))
    }

    func sendChat(_ message: ChatMessage, round: Round) async throws {
        guard let friend = round.players.first(where: { $0.id != "me" }) else { return }
        let replies = ["Nice one 👏", "Hit it straight this time 😂", "Drinks on the turn?", "Let's go!", "🔥🔥"]
        let reply = ChatMessage(author: friend, text: replies.randomElement()!)
        let id = round.id
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await self.push(.chat(reply), to: id)
        }
    }

    private func push(_ event: RoundEvent, to roundId: UUID) {
        listeners[roundId]?.yield(event)
    }

    nonisolated func roundEvents(_ round: Round) -> AsyncStream<RoundEvent> {
        AsyncStream { continuation in
            Task { await self.listen(round.id, continuation) }
        }
    }

    private func listen(_ id: UUID, _ continuation: AsyncStream<RoundEvent>.Continuation) {
        listeners[id] = continuation
    }

    func finish(_ round: Round) async throws {
        var finished = round
        finished.isActive = false
        rounds[round.id] = finished
        listeners[round.id]?.finish()
        listeners[round.id] = nil
    }

    func pastRounds() async throws -> [Round] {
        rounds.values.filter { !$0.isActive }.sorted { $0.date > $1.date }
    }

    // MARK: Drops

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

    func visit(drop: Drop, round: Round, at point: Coordinate) async throws {
        guard round.isActive, round.courseId == drop.courseId else { throw ClaimError.roundNotActive }
        guard drop.contains(point) else { throw ClaimError.outsideHole }
        visits.insert(drop.id)
    }

    func claim(drop: Drop, round: Round) async throws -> WonPrize {
        guard visits.contains(drop.id) else { throw ClaimError.outsideHole }
        guard !prizes.contains(where: { $0.drop.id == drop.id }) else { throw ClaimError.alreadyClaimed }
        let left = stock[drop.id] ?? drop.remaining
        guard left > 0 else { throw ClaimError.soldOut }
        if drop.challenge != .none {
            guard let strokes = round.strokes("me", hole: drop.holeNumber),
                  drop.challenge.isMet(strokes: strokes, par: round.pars[drop.holeNumber - 1]) else {
                throw ClaimError.challengeNotMet
            }
        }
        stock[drop.id] = left - 1
        var won = drop
        won.remaining = left - 1
        let prize = WonPrize(drop: won, code: "GIMME-" + String(UUID().uuidString.prefix(6)))
        prizes.insert(prize, at: 0)
        return prize
    }

    func wallet() async throws -> [WonPrize] { prizes }
}

enum BackendFactory {
    /// Supabase when the app is configured for it, otherwise the offline demo backend.
    static func make() -> any GimmeBackend {
        #if canImport(Supabase)
        if let live = SupabaseBackend.fromInfoPlist() { return live }
        #endif
        return MockBackend()
    }
}
