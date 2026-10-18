import Foundation
import Observation

/// App-wide state: the golfer, their friends and feed, the active round, drops and the prize wallet.
@MainActor
@Observable
final class AppState {
    let backend: any GimmeBackend
    let courses = CourseService()

    var me = Player(id: "me", name: "You", avatar: "🏌️")
    var friends: [Player] = []
    var feed: [FeedPost] = []

    var course: Course?
    var round: Round?
    var currentHole = 1
    var chat: [ChatMessage] = []
    var pastRounds: [Round] = []

    var drops: [Drop] = []
    var wallet: [WonPrize] = []
    /// Drops reached whose challenge is decided by this hole's score.
    var pendingChallenges: Set<String> = []
    /// Set when a prize is won; drives the "You found a drop!" sheet.
    var justWon: WonPrize?
    var message: String?

    private var triedDrops = Set<String>()
    private var lastPoint: Coordinate?

    init(backend: any GimmeBackend = MockBackend()) {
        self.backend = backend
    }

    func load() async {
        do {
            me = try await backend.currentUser()
            friends = try await backend.friends()
            feed = try await backend.feed()
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Round

    var hole: Hole? { course?.hole(currentHole) }

    func startRound(on course: Course, with group: [Player]) async {
        self.course = course
        round = Round(course: course, players: [me] + group)
        currentHole = course.holes.map(\.number).min() ?? 1
        pendingChallenges = []
        triedDrops = []
        chat = [ChatMessage(author: me, text: "On the first tee. Good luck everyone ⛳️")]
        drops = (try? await backend.drops(for: course)) ?? []
    }

    func setStrokes(_ strokes: Int?, for player: Player, hole number: Int) {
        round?.setStrokes(strokes, for: player.id, hole: number)
        guard player.id == me.id, let strokes else { return }
        // A challenge drop on this hole is decided the moment the golfer's own score goes in.
        for drop in drops where drop.holeNumber == number && pendingChallenges.contains(drop.id) {
            pendingChallenges.remove(drop.id)
            Task { await claim(drop, strokes: strokes) }
        }
    }

    func goToHole(_ number: Int) {
        guard let course, course.hole(number) != nil else { return }
        currentHole = number
    }

    func finishRound() async {
        guard var finished = round else { return }
        finished.isActive = false
        try? await backend.save(finished)
        pastRounds.insert(finished, at: 0)
        let post = FeedPost(author: me, kind: .round,
                            title: "Shot \(finished.total(me.id)) at \(finished.courseName)",
                            detail: "\(Scoring.formatToPar(finished.toPar(me.id))) thru \(finished.holesPlayed(me.id))")
        try? await backend.publish(post)
        feed = (try? await backend.feed()) ?? feed
        round = nil
        course = nil
        drops = []
    }

    func send(_ text: String) {
        chat.append(ChatMessage(author: me, text: text))
    }

    // MARK: GPS

    /// Called on each location fix during a round: follows the golfer to the hole they are on
    /// and checks every drop geofence.
    func handleLocation(_ point: Coordinate) async {
        guard let course, round?.isActive == true else { return }
        lastPoint = point

        // Auto-advance: if the golfer is standing on the next tee, move the hole view there.
        if let next = course.hole(currentHole + 1), Geo.meters(point, next.tee) < 25,
           round?.strokes(me.id, hole: currentHole) != nil {
            currentHole = next.number
        }

        for drop in drops where drop.holeNumber == currentHole && drop.contains(point) && !triedDrops.contains(drop.id) {
            triedDrops.insert(drop.id)
            if drop.challenge == .none {
                await claim(drop, strokes: nil)
            } else if let strokes = round?.strokes(me.id, hole: drop.holeNumber) {
                await claim(drop, strokes: strokes)
            } else {
                pendingChallenges.insert(drop.id)
                message = "🎁 \(drop.brand) drop on this hole. \(drop.challenge.label)!"
            }
        }
    }

    private func claim(_ drop: Drop, strokes: Int?) async {
        guard let round, let point = lastPoint else { return }
        do {
            let prize = try await backend.claim(drop: drop, round: round, at: point, holeStrokes: strokes)
            wallet.insert(prize, at: 0)
            if let i = drops.firstIndex(where: { $0.id == drop.id }) { drops[i].remaining = prize.drop.remaining }
            justWon = prize
        } catch {
            message = error.localizedDescription
        }
    }

    func share(_ prize: WonPrize) async {
        let post = FeedPost(author: me, kind: .drop,
                            title: "Won \(prize.drop.prize.lowercased()) on hole \(prize.drop.holeNumber)",
                            detail: "\(prize.drop.brand) drop on Gimme")
        try? await backend.publish(post)
        feed = (try? await backend.feed()) ?? feed
        chat.append(ChatMessage(author: me, text: "🎁 Just won \(prize.drop.prize) from \(prize.drop.brand)!"))
    }

    func toggleLike(_ post: FeedPost) {
        guard let i = feed.firstIndex(where: { $0.id == post.id }) else { return }
        feed[i].likedByMe.toggle()
        feed[i].likes += feed[i].likedByMe ? 1 : -1
    }

    var handicapEstimate: Double? {
        Scoring.handicapEstimate(rounds: pastRounds, playerId: me.id)
    }
}
