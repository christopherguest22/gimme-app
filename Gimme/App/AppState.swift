import Foundation
import Observation
import UserNotifications

/// App-wide state: the golfer, their friends and feed, the active round, drops and the prize wallet.
@MainActor
@Observable
final class AppState {
    let backend: any GimmeBackend
    let courses = CourseService()
    let scorecards = ScorecardService()
    let weather = ConditionsService()

    /// nil until the golfer signs in (or taps "Try the demo").
    var me: Player?
    var isLoading = true
    var friends: [Player] = []
    var feed: [FeedPost] = []

    var course: Course?
    var round: Round?
    var currentHole = 1
    /// The tees the golfer plays from, for scorecard yardages ("Blue").
    var selectedTee: String?
    /// Wind and temperature at the course, refreshed every few minutes during a round.
    var conditions: Conditions?
    private var conditionsFetched: Date?
    var bag = Bag.standard
    /// Tracked shots on each hole: where each shot was played from, in order.
    var shots: [Int: [Coordinate]] = [:]
    var chat: [ChatMessage] = []
    var pastRounds: [Round] = []

    var drops: [Drop] = []
    var wallet: [WonPrize] = []
    /// Drops reached whose challenge is decided by this hole's score.
    var pendingChallenges: Set<String> = []
    /// Set when a prize is won; drives the "You found a drop!" sheet.
    var justWon: WonPrize?
    var message: String?

    /// Friends can watch this round live while this is on.
    var isLive = false
    /// The golfer's own camera stream while live.
    let hostVideo = LiveVideo()
    /// The hottest clip someone posted on the hole the golfer is playing, shown on the GPS screen.
    var trendingHere: FeedPost?
    /// Post prizes won, trending holes and going live to the feed automatically.
    var shareActivity = UserDefaults.standard.object(forKey: "gimme.shareActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(shareActivity, forKey: "gimme.shareActivity") }
    }

    var isDemo: Bool { backend is MockBackend }

    private var triedDrops = Set<String>()
    private var lastPoint: Coordinate?
    private var liveUpdates: Task<Void, Never>?
    /// Holes this round where a trending post already went out, so it posts once per hole.
    private var trendingPosted = Set<Int>()
    private var livePositionSent: Date?

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
        clearAccount()
    }

    /// Deletes the account for good. Returns false, with the reason in `message`, if it failed.
    func deleteAccount() async -> Bool {
        do {
            if isLive { await setLive(false) }
            await hostVideo.stop()
            try await backend.deleteAccount()
            clearAccount()
            return true
        } catch {
            message = "Couldn't delete your account: \(error.localizedDescription)"
            return false
        }
    }

    private func clearAccount() {
        me = nil
        friends = []
        feed = []
        wallet = []
        pastRounds = []
    }

    // MARK: Safety

    /// Whether this golfer agreed to the Terms of Use (no tolerance for abusive content).
    var acceptedTerms = UserDefaults.standard.bool(forKey: "gimme.acceptedTerms") {
        didSet { UserDefaults.standard.set(acceptedTerms, forKey: "gimme.acceptedTerms") }
    }

    static let termsURL = infoURL("GimmeTermsURL")
    static let privacyURL = infoURL("GimmePrivacyURL")

    private static func infoURL(_ key: String) -> URL {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(URL.init(string:))
            ?? URL(string: "https://gimmegolf.app")!
    }

    /// Reports a post, comment or golfer for review, and hides a reported post right away.
    func report(_ target: ReportTarget, reason: String) async {
        do {
            try await backend.report(target, reason: reason)
            if case .post(let post) = target { feed.removeAll { $0.id == post.id } }
            message = "Thanks. We'll review it within 24 hours."
        } catch {
            message = "Report not sent: \(error.localizedDescription)"
        }
    }

    /// Blocks a golfer: their posts disappear and they can't see yours.
    func block(_ player: Player) async {
        do {
            try await backend.block(player)
            feed.removeAll { $0.author.id == player.id }
            friends.removeAll { $0.id == player.id }
            message = "\(player.name) is blocked."
        } catch {
            message = "Couldn't block \(player.name): \(error.localizedDescription)"
        }
    }

    func deletePost(_ post: FeedPost) async {
        do {
            try await backend.deletePost(post)
            feed.removeAll { $0.id == post.id }
        } catch {
            message = "Couldn't delete the post: \(error.localizedDescription)"
        }
    }

    func deleteComment(_ comment: FeedComment, on post: FeedPost) async -> Bool {
        do {
            try await backend.deleteComment(comment)
            if let i = feed.firstIndex(where: { $0.id == post.id }) { feed[i].comments -= 1 }
            return true
        } catch {
            message = "Couldn't delete the comment: \(error.localizedDescription)"
            return false
        }
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

    /// Builds a playable course: the hole shapes from OpenStreetMap, the scorecard (par, stroke
    /// index, yardage per tee) from the built-in course pack or OpenGolfAPI, any tee and green spots
    /// the golfer has set, and tee and green heights for plays-like distances.
    func prepareCourse(_ summary: CourseSummary) async throws -> Course {
        let pack = CoursePack.course(id: summary.id)
        var course: Course
        var mapError: Error?
        do {
            if let pack {
                course = try await courses.loadCourse(named: pack.osmName, near: pack.center)
                course.id = pack.id
                course.name = pack.name
            } else {
                course = try await courses.loadCourse(summary)
            }
        } catch {
            mapError = error
            course = Course(id: summary.id, name: summary.name, holes: [], source: "© OpenStreetMap contributors")
        }

        var card = pack?.scorecard
        if card == nil { card = try? await scorecards.scorecard(named: summary.name, near: summary.center) }
        if let card {
            course = ScorecardService.merge(card, into: course)
            // No map yet: lay the holes out from the scorecard so the course is playable, and let
            // the golfer pin the real tees and greens as they play.
            if course.holes.isEmpty, card.isConsistent {
                var standIn = DemoCourse.provisional(id: course.id, name: course.name, around: summary.center, card: card)
                standIn.tees = course.tees
                standIn = ScorecardService.merge(card, into: standIn)
                course = standIn
            }
        }
        course = HoleOverrides.apply(to: course)
        guard !course.holes.isEmpty else { throw mapError ?? CourseService.CourseError.noHoles }
        return await weather.addElevation(to: course)
    }

    /// The launch-area showcase course (the Ocean Course), loaded for the Home screen preview.
    /// Hole maps for courses shown on Home before a round starts, by course id.
    var previewCourses: [String: Course] = [:]

    func loadPreview(_ pack: PackCourse) async {
        guard previewCourses[pack.id] == nil else { return }
        if let course = try? await prepareCourse(pack.summary) { previewCourses[pack.id] = course }
    }

    /// The golfer's next booked round, kept on this phone.
    var teeTime: TeeTime? = TeeTime.saved {
        didSet { TeeTime.save(teeTime) }
    }

    /// Saves where this hole's tee or green really is (from the golfer's GPS) and moves it on the map.
    func setSpot(tee: Coordinate? = nil, green: Coordinate? = nil) {
        guard let course, let hole = course.hole(currentHole) else { return }
        var spot = HoleOverrides.load(course.id)[hole.number] ?? .init()
        if let tee { spot.tee = tee }
        if let green { spot.green = green }
        HoleOverrides.save(spot, hole: hole.number, courseId: course.id)
        self.course = HoleOverrides.apply(to: course)
    }

    func refreshConditions(force: Bool = false) async {
        guard let point = hole?.tee ?? course?.holes.first?.tee else { return }
        if !force, let conditionsFetched, Date().timeIntervalSince(conditionsFetched) < 600 { return }
        conditionsFetched = Date()
        if let latest = try? await weather.current(at: point) { conditions = latest }
    }

    /// Marks a shot played from `point` on the current hole.
    func trackShot(at point: Coordinate) {
        shots[currentHole, default: []].append(point)
    }

    func undoShot() {
        _ = shots[currentHole]?.popLast()
    }

    func startRound(on course: Course, with group: [Player], tee: String? = nil, stakes: Stakes? = nil) async {
        guard let me else { return }
        do {
            var new = Round(course: course, players: [me] + group)
            new.stakes = stakes?.isOn == true ? stakes : nil
            let started = try await backend.startRound(new, course: course)
            if teeTime?.courseId == course.id { teeTime = nil }
            self.course = course
            round = started
            currentHole = course.holes.map(\.number).min() ?? 1
            selectedTee = tee ?? course.teeNames.first
            shots = [:]
            conditions = nil
            conditionsFetched = nil
            Task { await refreshConditions(force: true) }
            pendingChallenges = []
            triedDrops = []
            chat = []
            drops = (try? await backend.drops(for: course)) ?? []
            listen(to: started)
            trendingPosted = []
            isLive = false
            Task { await holeChanged() }
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
        Task {
            await refreshConditions()
            await holeChanged()
        }
    }

    func finishRound() async {
        guard var finished = round, let me else { return }
        finished.isActive = false
        liveUpdates?.cancel()
        if isLive { await setLive(false) }
        await hostVideo.stop()
        trendingHere = nil
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

    // MARK: Side-game money

    /// Changes the stakes for the round on screen (or a finished one being settled) and tells the group.
    func setStakes(_ stakes: Stakes, for round: Round) {
        var updated = round
        updated.stakes = stakes.isOn ? stakes : nil
        save(updated)
        guard self.round?.id == round.id else { return }
        let parts = [stakes.perSkin > 0 ? "\(Settlement.money(stakes.perSkin)) a skin" : nil,
                     stakes.perNassauLeg > 0 ? "\(Settlement.money(stakes.perNassauLeg)) a Nassau leg" : nil].compactMap { $0 }
        send(parts.isEmpty ? "Side games are just for fun now." : "We're playing for " + parts.joined(separator: " and ") + ".")
    }

    /// Marks a settle-up payment as paid, or unmarks it.
    func togglePaid(_ payment: Payment, in round: Round) {
        var updated = round
        var paid = Set(updated.paid ?? [])
        if paid.contains(payment.id) { paid.remove(payment.id) } else { paid.insert(payment.id) }
        updated.paid = paid.sorted()
        save(updated)
    }

    func updatePayHandles(venmo: String, cashApp: String) async {
        let clean = { (s: String) -> String? in
            let trimmed = s.trimmingCharacters(in: CharacterSet(charactersIn: "@$ "))
            return trimmed.isEmpty ? nil : trimmed
        }
        do {
            me = try await backend.updatePayHandles(venmo: clean(venmo), cashApp: clean(cashApp))
        } catch {
            message = error.localizedDescription
        }
    }

    func updateHomeCourse(_ name: String?) async {
        do {
            me = try await backend.updateHomeCourse(name?.isEmpty == true ? nil : name)
        } catch {
            message = error.localizedDescription
        }
    }

    private func save(_ updated: Round) {
        if round?.id == updated.id { round = updated }
        if let i = pastRounds.firstIndex(where: { $0.id == updated.id }) { pastRounds[i] = updated }
        Task {
            do { try await backend.saveSideBets(updated) } catch { message = "Not saved: \(error.localizedDescription)" }
        }
    }

    /// A player as the app knows them now, so pay handles added after the round still show.
    func latest(_ player: Player) -> Player {
        if player.id == me?.id, let me { return me }
        return friends.first { $0.id == player.id } ?? player
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
            Task { await holeChanged() }
        }

        // Friends watching live see the golfer move, a few times a minute.
        if isLive, let round, Date.now.timeIntervalSince(livePositionSent ?? .distantPast) > 10 {
            livePositionSent = .now
            try? await backend.updateLivePosition(LivePosition(playerId: myId, hole: currentHole, point: point), round: round)
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
            if shareActivity { await share(prize) }
            Notifier.post(title: "You found a drop! 🎁", body: "\(prize.drop.brand): \(prize.drop.prize). It's in your wallet.")
        } catch {
            message = error.localizedDescription
        }
    }

    func share(_ prize: WonPrize) async {
        guard let me else { return }
        let post = FeedPost(author: me, kind: .drop,
                            title: "Won \(prize.drop.prize.lowercased()) on \(prize.drop.holeNumber)",
                            detail: "\(prize.drop.brand) drop on Gimme",
                            courseId: course?.id, courseName: course?.name, hole: prize.drop.holeNumber,
                            imageURL: prize.drop.imageURL)
        try? await backend.publish(post)
        feed = (try? await backend.feed()) ?? feed
        if round != nil { send("🎁 Just won \(prize.drop.prize) from \(prize.drop.brand)!") }
    }

    // MARK: Feed

    /// Likes or congratulates a post, or takes it back. Updates on screen first.
    func toggle(_ reaction: Reaction, on post: FeedPost) {
        guard let i = feed.firstIndex(where: { $0.id == post.id }) else { return }
        let on: Bool
        switch reaction {
        case .like:
            feed[i].likedByMe.toggle()
            on = feed[i].likedByMe
            feed[i].likes += on ? 1 : -1
        case .congrats:
            feed[i].congratsByMe.toggle()
            on = feed[i].congratsByMe
            feed[i].congrats += on ? 1 : -1
        }
        let saved = feed[i]
        Task { try? await backend.react(reaction, on: saved, on) }
    }

    func comments(on post: FeedPost) async -> [FeedComment] {
        (try? await backend.comments(on: post)) ?? []
    }

    func comment(_ text: String, on post: FeedPost) async -> FeedComment? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, let comment = try? await backend.comment(clean, on: post) else { return nil }
        if let i = feed.firstIndex(where: { $0.id == post.id }) { feed[i].comments += 1 }
        return comment
    }

    /// Counts a play of someone else's clip.
    func viewed(_ post: FeedPost) {
        guard post.kind == .clip, post.author.id != myId else { return }
        if let i = feed.firstIndex(where: { $0.id == post.id }) { feed[i].views += 1 }
        Task { try? await backend.recordView(post) }
    }

    /// Uploads a clip and posts it, tagged with the hole when it was filmed during a round.
    func postClip(_ file: URL, caption: String, audience: FeedPost.Audience) async -> Bool {
        guard let me else { return false }
        do {
            let url = try await backend.uploadClip(file)
            let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let playing = round != nil
            let post = FeedPost(author: me, kind: .clip,
                                title: text.isEmpty ? (playing ? "On \(currentHole) at \(course?.name ?? "the course")" : "New clip") : text,
                                detail: "", audience: audience,
                                courseId: playing ? course?.id : nil, courseName: playing ? course?.name : nil,
                                hole: playing ? currentHole : nil, videoURL: url, roundId: round?.id)
            try await backend.publish(post)
            feed.insert(post, at: 0)
            if playing { send("🎥 Posted a clip from \(currentHole)") }
            return true
        } catch {
            message = "Clip not posted: \(error.localizedDescription)"
            return false
        }
    }

    /// On reaching a hole: find the clip that's trending there, show it on the GPS screen, and
    /// tell the feed the golfer is taking it on.
    private func holeChanged() async {
        guard let course, round != nil else { return }
        let hole = currentHole
        if let latest = try? await backend.feed() { feed = latest }
        guard hole == currentHole else { return }
        trendingHere = Trending.clip(on: hole, courseId: course.id, in: feed, excluding: myId)
        guard let clip = trendingHere, shareActivity, !trendingPosted.contains(hole), let me else { return }
        trendingPosted.insert(hole)
        let post = FeedPost(author: me, kind: .trending,
                            title: "\(me.name) is on \(hole) at \(course.name)",
                            detail: "Where \(clip.author.name)'s clip \u{201C}\(clip.title)\u{201D} is trending. Can \(me.name) top it?",
                            courseId: course.id, courseName: course.name, hole: hole, refPostId: clip.id)
        try? await backend.publish(post)
        feed.insert(post, at: 0)
    }

    // MARK: Going live

    /// Lets friends watch this round: where the golfer is on the hole, the scores, their clips,
    /// and their camera when they turn it on.
    func setLive(_ live: Bool) async {
        guard let round, let me else { return }
        do {
            try await backend.setLive(round, live)
            isLive = live
            guard live else { return }
            if let point = lastPoint {
                livePositionSent = .now
                try? await backend.updateLivePosition(LivePosition(playerId: myId, hole: currentHole, point: point), round: round)
            }
            if shareActivity {
                let post = FeedPost(author: me, kind: .live, title: "\(me.name) is live at \(round.courseName)",
                                    detail: "Tap in and follow along.", courseId: round.courseId, courseName: round.courseName,
                                    roundId: round.id)
                try? await backend.publish(post)
                feed.insert(post, at: 0)
            }
            send("🔴 I'm live. Friends can watch the round from Community.")
        } catch {
            message = "Couldn't go live: \(error.localizedDescription)"
        }
    }

    /// Where to stream the round's camera, or watch it: a LiveKit server and an access token.
    func videoAccess(roundId: UUID, publish: Bool) async -> LiveVideoAccess? {
        try? await backend.liveVideoAccess(roundId: roundId, publish: publish)
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
