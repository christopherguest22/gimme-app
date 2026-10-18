import Foundation
import Observation
import UserNotifications

/// App-wide state: the golfer, their friends and feed, the active round, drops and the prize wallet.
@MainActor
@Observable
final class AppState {
    let backend: any GimmeBackend
    let courses = CourseService()

    /// nil until the golfer signs in (or taps "Try the demo").
    var me: Player?
    var isLoading = true
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

    var isDemo: Bool { backend is MockBackend }

    private var triedDrops = Set<String>()
    private var lastPoint: Coordinate?
    private var liveUpdates: Task<Void, Never>?

    init(backend: any GimmeBackend = BackendFactory.make()) {
        self.backend = backend
    }

    /// The signed-in id, or a placeholder before sign-in.
    var myId: String { me?.id ?? "me" }

    func load() async {
        defer { isLoading = false }
        do {
            me = try await backend.currentUser()
            guard me != nil else { return }
            async let friendList = backend.friends()
            async let posts = backend.feed()
            async let prizes = backend.wallet()
            async let rounds = backend.pastRounds()
            friends = try await friendList
            feed = try await posts
            wallet = try await prizes
            pastRounds = try await rounds
        } catch {
            message = error.localizedDescription
        }
    }

    // MARK: Account

    func sendCode(to email: String) async -> Bool {
        do {
            try await backend.sendSignInCode(email: email)
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func verify(email: String, code: String) async {
        do {
            me = try await backend.verifySignInCode(email: email, code: code)
            await load()
        } catch {
            message = error.localizedDescription
        }
    }

    func updateProfile(name: String, avatar: String) async {
        do {
            me = try await backend.updateProfile(name: name, avatar: avatar)
        } catch {
            message = error.localizedDescription
        }
    }

    func signOut() async {
        try? await backend.signOut()
        me = nil
        friends = []
        feed = []
        wallet = []
        pastRounds = []
    }

    func addFriend(_ handle: String) async {
        do {
            try await backend.addFriend(handle: handle)
            friends = try await backend.friends()
        } catch {
            message = error.localizedDescription
        }
    }

    func post(_ text: String) async {
        guard let me else { return }
        try? await backend.publish(FeedPost(author: me, kind: .note, title: text, detail: ""))
        feed = (try? await backend.feed()) ?? feed
    }

    // MARK: Round

    var hole: Hole? { course?.hole(currentHole) }

    func startRound(on course: Course, with group: [Player]) async {
        guard let me else { return }
        do {
            let started = try await backend.startRound(Round(course: course, players: [me] + group), course: course)
            self.course = course
            round = started
            currentHole = course.holes.map(\.number).min() ?? 1
            pendingChallenges = []
            triedDrops = []
            chat = []
            drops = (try? await backend.drops(for: course)) ?? []
            listen(to: started)
            Notifier.requestPermission()
        } catch {
            message = error.localizedDescription
        }
    }

    /// Applies score and chat changes made on the other phones in the group.
    private func listen(to round: Round) {
        liveUpdates?.cancel()
        let events = backend.roundEvents(round)
        liveUpdates = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case let .score(playerId, hole, strokes):
                    self.round?.setStrokes(strokes, for: playerId, hole: hole)
                case let .chat(message):
                    if !self.chat.contains(where: { $0.id == message.id }) { self.chat.append(message) }
                }
            }
        }
    }

    func setStrokes(_ strokes: Int?, for player: Player, hole number: Int) {
        guard let current = round else { return }
        round?.setStrokes(strokes, for: player.id, hole: number)
        Task {
            do {
                try await backend.saveScore(round: current, playerId: player.id, hole: number, strokes: strokes)
            } catch {
                message = "Score not saved: \(error.localizedDescription)"
            }
        }
        guard player.id == myId, strokes != nil else { return }
        // A challenge drop on this hole is decided the moment the golfer's own score goes in.
        for drop in drops where drop.holeNumber == number && pendingChallenges.contains(drop.id) {
            pendingChallenges.remove(drop.id)
            Task { await claim(drop) }
        }
    }

    func goToHole(_ number: Int) {
        guard let course, course.hole(number) != nil else { return }
        currentHole = number
    }

    func finishRound() async {
        guard var finished = round, let me else { return }
        finished.isActive = false
        liveUpdates?.cancel()
        try? await backend.finish(finished)
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
        guard let me, let round else { return }
        let message = ChatMessage(author: me, text: text)
        chat.append(message)
        Task { try? await backend.sendChat(message, round: round) }
    }

    // MARK: GPS and drops

    /// Called on each location fix during a round (also in the background): follows the golfer
    /// to the hole they are on and checks every drop geofence.
    func handleLocation(_ point: Coordinate) async {
        guard let course, round?.isActive == true else { return }
        lastPoint = point

        // Auto-advance: if the golfer is standing on the next tee, move the hole view there.
        if let next = course.hole(currentHole + 1), Geo.meters(point, next.tee) < 25,
           round?.strokes(myId, hole: currentHole) != nil {
            currentHole = next.number
        }

        for drop in drops where drop.contains(point) && !triedDrops.contains(drop.id) {
            triedDrops.insert(drop.id)
            guard let round else { return }
            do {
                try await backend.visit(drop: drop, round: round, at: point)
            } catch {
                triedDrops.remove(drop.id) // try again on the next fix
                continue
            }
            if drop.challenge == .none || round.strokes(myId, hole: drop.holeNumber) != nil {
                await claim(drop)
            } else {
                pendingChallenges.insert(drop.id)
                message = "🎁 \(drop.brand) drop on this hole. \(drop.challenge.label)!"
                Notifier.post(title: "Prize drop on hole \(drop.holeNumber)!",
                              body: "\(drop.brand): \(drop.prize). \(drop.challenge.label).")
            }
        }
    }

    private func claim(_ drop: Drop) async {
        guard let round else { return }
        do {
            let prize = try await backend.claim(drop: drop, round: round)
            wallet.insert(prize, at: 0)
            if let i = drops.firstIndex(where: { $0.id == drop.id }) { drops[i].remaining = prize.drop.remaining }
            justWon = prize
            Notifier.post(title: "You found a drop! 🎁", body: "\(prize.drop.brand): \(prize.drop.prize). It's in your wallet.")
        } catch {
            message = error.localizedDescription
        }
    }

    func share(_ prize: WonPrize) async {
        guard let me else { return }
        let post = FeedPost(author: me, kind: .drop,
                            title: "Won \(prize.drop.prize.lowercased()) on hole \(prize.drop.holeNumber)",
                            detail: "\(prize.drop.brand) drop on Gimme")
        try? await backend.publish(post)
        feed = (try? await backend.feed()) ?? feed
        if round != nil { send("🎁 Just won \(prize.drop.prize) from \(prize.drop.brand)!") }
    }

    func toggleLike(_ post: FeedPost) {
        guard let i = feed.firstIndex(where: { $0.id == post.id }) else { return }
        feed[i].likedByMe.toggle()
        feed[i].likes += feed[i].likedByMe ? 1 : -1
    }

    var handicapEstimate: Double? {
        Scoring.handicapEstimate(rounds: pastRounds, playerId: myId)
    }
}

/// Local notifications so a drop found with the phone in a pocket still gets noticed.
enum Notifier {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
