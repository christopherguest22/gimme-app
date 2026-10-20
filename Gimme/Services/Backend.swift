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
    /// Venmo username and Cash App $cashtag, so the group can pay side games.
    func updatePayHandles(venmo: String?, cashApp: String?) async throws -> Player
    /// The course shown under the golfer's name on their posts.
    func updateHomeCourse(_ name: String?) async throws -> Player
    func signOut() async throws
    /// Deletes the golfer's account and everything they posted (App Store rule 5.1.1(v)).
    func deleteAccount() async throws

    // Friends and feed
    func friends() async throws -> [Player]
    func addFriend(handle: String) async throws
    /// Everything the golfer can see: public clips from anyone, and friends' posts.
    func feed() async throws -> [FeedPost]
    func publish(_ post: FeedPost) async throws
    /// Uploads a recorded clip and returns where it can be played from.
    func uploadClip(_ file: URL) async throws -> URL
    func react(_ reaction: Reaction, on post: FeedPost, _ on: Bool) async throws
    func comments(on post: FeedPost) async throws -> [FeedComment]
    func comment(_ text: String, on post: FeedPost) async throws -> FeedComment
    func recordView(_ post: FeedPost) async throws
    func deletePost(_ post: FeedPost) async throws
    func deleteComment(_ comment: FeedComment) async throws
    /// Hides each other's posts, comments and cheers, and ends the friendship.
    func block(_ player: Player) async throws
    func report(_ target: ReportTarget, reason: String) async throws

    // Going live
    /// Starts or stops letting friends watch this round.
    func setLive(_ round: Round, _ live: Bool) async throws
    func updateLivePosition(_ position: LivePosition, round: Round) async throws
    /// A friend's live round and its course map, for watching.
    func watch(roundId: UUID) async throws -> (round: Round, course: Course?)
    func liveEvents(roundId: UUID) -> AsyncStream<LiveEvent>
    func cheer(_ text: String, roundId: UUID) async throws
    /// Credentials for streaming (`publish`) or watching the round's camera.
    func liveVideoAccess(roundId: UUID, publish: Bool) async throws -> LiveVideoAccess

    // Rounds
    func startRound(_ round: Round, course: Course) async throws -> Round
    func saveScore(round: Round, playerId: String, hole: Int, strokes: Int?) async throws
    func sendChat(_ message: ChatMessage, round: Round) async throws
    func roundEvents(_ round: Round) -> AsyncStream<RoundEvent>
    func finish(_ round: Round) async throws
    /// Saves the round's stakes and which settle-up payments are marked paid.
    func saveSideBets(_ round: Round) async throws
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
        Player(id: "jake", name: "Jake", avatar: "🧢", handicap: 8.4, playingNow: "Hole 6 at Turtle Point", venmo: "demo-jake"),
        Player(id: "maria", name: "Maria", avatar: "⛳️", handicap: 14.2, cashApp: "demomaria"),
        Player(id: "dev", name: "Dev", avatar: "🦅", handicap: 3.1, playingNow: "Hole 14 at Osprey Point", venmo: "demo-dev"),
        Player(id: "sam", name: "Sam", avatar: "🍺", handicap: 21.7),
    ]
    private var posts: [FeedPost] = []
    private var stock: [String: Int] = [:]
    private var visits = Set<String>()
    private var prizes: [WonPrize] = []
    private var rounds: [UUID: Round] = [:]
    private var listeners: [UUID: AsyncStream<RoundEvent>.Continuation] = [:]
    private var commentsByPost: [UUID: [FeedComment]] = [:]
    /// Jake's round at Turtle Point, streaming live in the demo.
    private let jakesRound = UUID()

    init() {
        friendList[0].homeCourse = "Turtle Point"
        friendList[0].liveRoundId = jakesRound
        friendList[1].homeCourse = "Osprey Point"
        friendList[2].homeCourse = "The Ocean Course"
        friendList[3].homeCourse = "Cougar Point"
        let ocean = CoursePack.featured
        let stranger = Player(id: "kiawah-kate", name: "Kate R.", avatar: "🐯", handicap: 5.6, homeCourse: "The Ocean Course")
        posts = [
            FeedPost(author: friendList[0], kind: .live, title: "Jake is live at Turtle Point",
                     detail: "Tap in and follow along.", postedAt: .now.addingTimeInterval(-1_500),
                     courseName: "Turtle Point", roundId: jakesRound),
            FeedPost(author: stranger, kind: .clip, title: "Stuck it to 3 feet on 17",
                     detail: "Over the water with a 6 iron, into the wind. #oceancourse",
                     postedAt: .now.addingTimeInterval(-6 * 86_400), likes: 412, comments: 38, views: 9_870,
                     audience: .everyone, courseId: ocean?.id, courseName: ocean?.name, hole: 17),
            FeedPost(author: friendList[2], kind: .clip, title: "Drained it on 18",
                     detail: "30 footer for birdie in front of the clubhouse.", postedAt: .now.addingTimeInterval(-2 * 86_400),
                     likes: 96, comments: 12, views: 1_430, audience: .everyone,
                     courseId: ocean?.id, courseName: ocean?.name, hole: 18),
            FeedPost(author: friendList[2], kind: .round, title: "Shot 71 at The Ocean Course",
                     detail: "-1 with 4 birdies. Putter was hot.", postedAt: .now.addingTimeInterval(-3_600), likes: 6, congrats: 9),
            FeedPost(author: friendList[0], kind: .drop, title: "Won a Fore the Carolinas Rope Hat on 18",
                     detail: "Par on the last at the Ocean Course. Palmetto & Pine drop.", postedAt: .now.addingTimeInterval(-7_200),
                     likes: 3, congrats: 14, courseId: ocean?.id, courseName: ocean?.name, hole: 18,
                     imageURL: URL(string: "https://palmettoandpinegolf.com/cdn/shop/files/Product_Photos_20.png?v=1729101055&width=1080")),
            FeedPost(author: friendList[1], kind: .note, title: "Saturday 8:10am at Osprey, who's in?",
                     detail: "Need a fourth.", postedAt: .now.addingTimeInterval(-86_400), likes: 2, comments: 1),
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
        var player = me ?? Player(id: "me", name: name, avatar: avatar)
        player.name = name
        player.avatar = avatar
        me = player
        return player
    }

    func updatePayHandles(venmo: String?, cashApp: String?) async throws -> Player {
        var player = me ?? Player(id: "me", name: "You", avatar: "🏌️")
        player.venmo = venmo
        player.cashApp = cashApp
        me = player
        return player
    }

    func updateHomeCourse(_ name: String?) async throws -> Player {
        var player = me ?? Player(id: "me", name: "You", avatar: "🏌️")
        player.homeCourse = name
        me = player
        return player
    }

    func signOut() async throws { me = nil }

    func deleteAccount() async throws {
        posts.removeAll { $0.author.id == "me" || $0.author.id == me?.id }
        prizes = []
        me = nil
    }

    // MARK: Friends and feed

    func friends() async throws -> [Player] { friendList }

    func addFriend(handle: String) async throws {
        let name = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).capitalized
        guard !name.isEmpty, !friendList.contains(where: { $0.name == name }) else { return }
        friendList.append(Player(id: name.lowercased(), name: name, avatar: "🙂"))
    }

    func feed() async throws -> [FeedPost] { posts.sorted { $0.postedAt > $1.postedAt } }
    func publish(_ post: FeedPost) async throws { posts.append(post) }

    /// Demo clips stay on the phone.
    func uploadClip(_ file: URL) async throws -> URL { file }

    func react(_ reaction: Reaction, on post: FeedPost, _ on: Bool) async throws {
        guard let i = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let change = on ? 1 : -1
        switch reaction {
        case .like:
            posts[i].likedByMe = on
            posts[i].likes += change
        case .congrats:
            posts[i].congratsByMe = on
            posts[i].congrats += change
        }
    }

    func comments(on post: FeedPost) async throws -> [FeedComment] {
        if let saved = commentsByPost[post.id] { return saved }
        let samples = ["Pure 🔥", "What club was that?", "Congrats!", "Next round is on you 😂", "That green is so fast"]
        let sample = (0..<min(post.comments, 3)).map { i in
            FeedComment(author: friendList[i % friendList.count], text: samples[i % samples.count],
                        postedAt: post.postedAt.addingTimeInterval(Double(i + 1) * 600))
        }
        commentsByPost[post.id] = sample
        return sample
    }

    func comment(_ text: String, on post: FeedPost) async throws -> FeedComment {
        let comment = FeedComment(author: me ?? Player(id: "me", name: "You", avatar: "🏌️"), text: text)
        commentsByPost[post.id, default: []].append(comment)
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].comments += 1 }
        return comment
    }

    func recordView(_ post: FeedPost) async throws {
        if let i = posts.firstIndex(where: { $0.id == post.id }) { posts[i].views += 1 }
    }

    func deletePost(_ post: FeedPost) async throws { posts.removeAll { $0.id == post.id } }

    func deleteComment(_ comment: FeedComment) async throws {
        for (post, list) in commentsByPost where list.contains(where: { $0.id == comment.id }) {
            commentsByPost[post] = list.filter { $0.id != comment.id }
            if let i = posts.firstIndex(where: { $0.id == post }) { posts[i].comments -= 1 }
        }
    }

    func block(_ player: Player) async throws {
        posts.removeAll { $0.author.id == player.id }
        friendList.removeAll { $0.id == player.id }
        for (post, list) in commentsByPost { commentsByPost[post] = list.filter { $0.author.id != player.id } }
    }

    /// The demo has no one to review reports; the post is just hidden for this golfer.
    func report(_ target: ReportTarget, reason: String) async throws {
        if case .post(let post) = target { posts.removeAll { $0.id == post.id } }
    }

    // MARK: Going live

    func setLive(_ round: Round, _ live: Bool) async throws {}
    func updateLivePosition(_ position: LivePosition, round: Round) async throws {}

    /// Jake's demo round: Turtle Point, a few holes in, laid out from the scorecard.
    func watch(roundId: UUID) async throws -> (round: Round, course: Course?) {
        guard roundId == jakesRound, let pack = CoursePack.courses.first(where: { $0.name == "Turtle Point" }) ?? CoursePack.featured else {
            throw URLError(.resourceUnavailable)
        }
        let course = DemoCourse.provisional(id: pack.id, name: pack.name, around: pack.center, card: pack.scorecard)
        var round = Round(course: course, players: [friendList[0], friendList[3]])
        round.id = jakesRound
        let jake = [4, 5, 3, 4, 4], sam = [5, 6, 4, 5, 5]
        for hole in 1...5 {
            round.setStrokes(jake[hole - 1], for: "jake", hole: hole)
            round.setStrokes(sam[hole - 1], for: "sam", hole: hole)
        }
        return (round, course)
    }

    /// Jake walks hole 6, finishes it, and friends cheer along.
    nonisolated func liveEvents(roundId: UUID) -> AsyncStream<LiveEvent> {
        AsyncStream { continuation in
            let task = Task {
                guard let watched = try? await self.watch(roundId: roundId), let hole = watched.course?.hole(6) else { return }
                let round = watched.round
                let cheers = [("maria", "Go Jake! 🏌️"), ("dev", "Fairways and greens"), ("maria", "That's a birdie putt 👀")]
                let friends = await self.friendsNow
                for step in 0...12 {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if Task.isCancelled { return }
                    let along = Geo.offset(hole.tee, meters: Geo.meters(hole.tee, hole.greenCenter) * min(Double(step) / 10, 1),
                                           bearing: hole.bearing)
                    continuation.yield(.position(LivePosition(playerId: "jake", hole: 6, point: along)))
                    if step % 4 == 1, let cheer = cheers[safe: step / 4],
                       let author = friends.first(where: { $0.id == cheer.0 }) {
                        continuation.yield(.cheer(LiveCheer(author: author, text: cheer.1)))
                    }
                }
                continuation.yield(.score(playerId: "jake", hole: 6, strokes: round.pars[5] - 1))
                continuation.yield(.score(playerId: "sam", hole: 6, strokes: round.pars[5] + 1))
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private var friendsNow: [Player] { friendList }

    func cheer(_ text: String, roundId: UUID) async throws {}

    /// The demo has no video server; the tracker still works.
    func liveVideoAccess(roundId: UUID, publish: Bool) async throws -> LiveVideoAccess { throw LiveVideoError.notSetUp }

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

    func saveSideBets(_ round: Round) async throws {
        rounds[round.id]?.stakes = round.stakes
        rounds[round.id]?.paid = round.paid
    }

    func pastRounds() async throws -> [Round] {
        rounds.values.filter { !$0.isActive }.sorted { $0.date > $1.date }
    }

    // MARK: Drops

    /// The beta's launch partner, Palmetto & Pine Golf Co., on four holes of any course.
    func drops(for course: Course) async throws -> [Drop] {
        let pp = "https://palmettoandpinegolf.com"
        let offers: [(hole: Int, brand: String, prize: String, detail: String, challenge: Drop.Challenge, count: Int,
                      headline: String, imageURL: String, claimURL: String)] = [
            (5, "Palmetto & Pine", "Free Laid Back Ball Marker",
             "The Laid Back Ball Marker from Palmetto & Pine, on the house for beta testers.", .none, 10,
             "Mark it down. You\u{2019}re officially \u{201C}Laid Back\u{201D}",
             pp + "/cdn/shop/files/ProductPhotos_4b5f0c15-e346-47c8-93f8-a1d705ad1a44.png?v=1787250279&width=1080",
             pp + "/products/the-laid-back-ball-marker-c3-custom-golf"),
            (7, "Palmetto & Pine", "Free Dogwood & Jessamine Caddie Towel",
             "Dogwood & Jessamine Caddie Towel from Palmetto & Pine, on the house for beta testers.", .none, 8,
             "Clean round, clean clubs. A Dogwood & Jessamine towel is yours",
             pp + "/cdn/shop/files/Product_Photos_8_5e4693bb-6827-4f9f-bc5f-accbacd1d787.png?v=1778599117&width=1080",
             pp + "/products/dogwood-jessamine-caddie-towel"),
            (12, "Palmetto & Pine", "Free Carolina Comfort Hoodie",
             "The Carolina Comfort Hoodie from Palmetto & Pine, on the house for beta testers.", .birdieOrBetter, 3,
             "Birdie? That\u{2019}s some real \u{201C}Carolina Comfort\u{201D}",
             pp + "/cdn/shop/files/Product_Photos_6_b4d3d496-5d5d-4d8d-8403-4b9556bbd653.png?v=1760987557&width=1080",
             pp + "/products/the-carolina-comfort-hoodie"),
            (18, "Palmetto & Pine", "Free Fore the Carolinas Rope Hat",
             "Fore the Carolinas Rope Hat from Palmetto & Pine, on the house for beta testers.", .parOrBetter, 6,
             "Congrats! You just went \u{201C}Fore the Carolinas\u{201D}",
             pp + "/cdn/shop/files/Product_Photos_20.png?v=1729101055&width=1080",
             pp + "/products/fore-the-carolinas-rope-hat"),
        ]
        return offers.compactMap { offer in
            guard let hole = course.hole(offer.hole) else { return nil }
            let id = "\(course.id)-\(offer.hole)"
            return Drop(id: id, brand: offer.brand, prize: offer.prize, detail: offer.detail,
                        courseId: course.id, holeNumber: offer.hole, center: hole.greenCenter,
                        radiusMeters: 45, challenge: offer.challenge,
                        remaining: stock[id] ?? offer.count,
                        expires: Calendar.current.date(byAdding: .day, value: 30, to: .now)!,
                        headline: offer.headline, imageURL: URL(string: offer.imageURL), claimURL: URL(string: offer.claimURL))
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
