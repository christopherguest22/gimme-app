#if canImport(Supabase)
import Foundation
import Supabase

/// The real backend: Supabase auth, Postgres tables and realtime (see supabase/schema.sql).
/// Turned on by setting `SupabaseURL` and `SupabaseAnonKey` in the app's Info.plist (project.yml).
final class SupabaseBackend: GimmeBackend {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    static func fromInfoPlist() -> SupabaseBackend? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let url = URL(string: urlString), !urlString.isEmpty,
              let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String, !key.isEmpty
        else { return nil }
        return SupabaseBackend(client: SupabaseClient(supabaseURL: url, supabaseKey: key))
    }

    private func userId() async throws -> String {
        try await client.auth.session.user.id.uuidString.lowercased()
    }

    // MARK: Account

    func currentUser() async throws -> Player? {
        guard let session = try? await client.auth.session else { return nil }
        return try await profile(session.user.id.uuidString.lowercased())
    }

    func sendSignInCode(email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    func verifySignInCode(email: String, code: String) async throws -> Player {
        // A password instead of the emailed digits: the App Review account, which can't get our emails.
        if code.contains(where: { !$0.isNumber }) {
            let session = try await client.auth.signIn(email: email, password: code)
            return try await profile(session.user.id.uuidString.lowercased())
        }
        let response = try await client.auth.verifyOTP(email: email, token: code, type: .email)
        return try await profile(response.user.id.uuidString.lowercased())
    }

    func updateProfile(name: String, avatar: String) async throws -> Player {
        let id = try await userId()
        try await client.from("profiles").update(["name": name, "avatar": avatar]).eq("id", value: id).execute()
        return try await profile(id)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Removes the golfer's clips from storage, then their data and login (see delete_account()).
    func deleteAccount() async throws {
        let id = try await userId()
        let clips = client.storage.from("clips")
        let files = (try? await clips.list(path: id)) ?? []
        if !files.isEmpty { _ = try? await clips.remove(paths: files.map { "\(id)/\($0.name)" }) }
        try await client.rpc("delete_account").execute()
        try? await client.auth.signOut(scope: .local)
    }

    func updatePayHandles(venmo: String?, cashApp: String?) async throws -> Player {
        let id = try await userId()
        try await client.from("profiles").update(["venmo": venmo, "cash_app": cashApp]).eq("id", value: id).execute()
        return try await profile(id)
    }

    func updateHomeCourse(_ name: String?) async throws -> Player {
        let id = try await userId()
        try await client.from("profiles").update(["home_course": name]).eq("id", value: id).execute()
        return try await profile(id)
    }

    private func profile(_ id: String) async throws -> Player {
        let row: ProfileRow = try await client.from("profiles").select().eq("id", value: id).single().execute().value
        return row.player
    }

    // MARK: Friends and feed

    func friends() async throws -> [Player] {
        let id = try await userId()
        let rows: [FriendRow] = try await client.from("friendships")
            .select("friend:profiles!friendships_friend_id_fkey(*)")
            .eq("user_id", value: id)
            .execute().value
        var players = rows.map(\.friend.player).sorted { $0.name < $1.name }
        // Friends streaming a round right now (the policy only shows live rounds of friends).
        let live: [LiveRoundRow] = (try? await client.from("rounds")
            .select("id, created_by, live, finished_at")
            .eq("live", value: true)
            .filter("finished_at", operator: "is", value: "null")
            .execute().value) ?? []
        for row in live {
            if let i = players.firstIndex(where: { $0.id == row.created_by?.uuidString.lowercased() }) {
                players[i].liveRoundId = row.id
            }
        }
        return players
    }

    func addFriend(handle: String) async throws {
        let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
        try await client.rpc("add_friend", params: ["p_handle": clean]).execute()
    }

    func feed() async throws -> [FeedPost] {
        let rows: [FeedRow] = try await client.from("feed_view")
            .select()
            .order("posted_at", ascending: false)
            .limit(100)
            .execute().value
        return rows.map(\.post)
    }

    func publish(_ post: FeedPost) async throws {
        try await client.from("feed_posts").insert(FeedInsert(post)).execute()
    }

    /// Clips go in the public `clips` bucket, in a folder named for the golfer.
    func uploadClip(_ file: URL) async throws -> URL {
        let id = try await userId()
        let path = "\(id)/\(UUID().uuidString.lowercased()).\(file.pathExtension.isEmpty ? "mov" : file.pathExtension.lowercased())"
        let data = try Data(contentsOf: file)
        try await client.storage.from("clips")
            .upload(path, data: data, options: FileOptions(contentType: file.pathExtension.lowercased() == "mp4" ? "video/mp4" : "video/quicktime"))
        return try client.storage.from("clips").getPublicURL(path: path)
    }

    func react(_ reaction: Reaction, on post: FeedPost, _ on: Bool) async throws {
        if on {
            try await client.from("post_reactions")
                .upsert(ReactionRow(post_id: post.id, kind: reaction.rawValue), ignoreDuplicates: true)
                .execute()
        } else {
            try await client.from("post_reactions").delete()
                .eq("post_id", value: post.id.uuidString.lowercased())
                .eq("user_id", value: try await userId())
                .eq("kind", value: reaction.rawValue)
                .execute()
        }
    }

    func comments(on post: FeedPost) async throws -> [FeedComment] {
        let rows: [CommentRow] = try await client.from("post_comments")
            .select("id, body, posted_at, author:profiles(*)")
            .eq("post_id", value: post.id.uuidString.lowercased())
            .order("posted_at", ascending: true)
            .execute().value
        return rows.map(\.comment)
    }

    func comment(_ text: String, on post: FeedPost) async throws -> FeedComment {
        let row: CommentRow = try await client.from("post_comments")
            .insert(CommentInsert(post_id: post.id, body: text))
            .select("id, body, posted_at, author:profiles(*)")
            .single()
            .execute().value
        return row.comment
    }

    func recordView(_ post: FeedPost) async throws {
        try await client.rpc("record_view", params: ["p_post": post.id]).execute()
    }

    func deletePost(_ post: FeedPost) async throws {
        try await client.from("feed_posts").delete().eq("id", value: post.id.uuidString.lowercased()).execute()
    }

    func deleteComment(_ comment: FeedComment) async throws {
        try await client.from("post_comments").delete().eq("id", value: comment.id.uuidString.lowercased()).execute()
    }

    func block(_ player: Player) async throws {
        let me = try await userId()
        try await client.from("blocks").upsert(BlockRow(blocked_id: player.id), ignoreDuplicates: true).execute()
        try await client.from("friendships").delete()
            .or("and(user_id.eq.\(me),friend_id.eq.\(player.id)),and(user_id.eq.\(player.id),friend_id.eq.\(me))")
            .execute()
    }

    func report(_ target: ReportTarget, reason: String) async throws {
        var row = ReportInsert(reason: reason, user_id: target.author.id)
        switch target {
        case .post(let post): row.post_id = post.id
        case .comment(let comment): row.comment_id = comment.id
        case .player: break
        }
        try await client.from("reports").insert(row).execute()
    }

    // MARK: Going live

    func setLive(_ round: Round, _ live: Bool) async throws {
        try await client.rpc("set_live", params: LiveParams(p_round: round.id, p_live: live)).execute()
    }

    func updateLivePosition(_ position: LivePosition, round: Round) async throws {
        try await client.from("live_positions")
            .upsert(PositionRow(round_id: round.id, player_id: UUID(uuidString: position.playerId),
                                hole: position.hole, lat: position.point.latitude, lon: position.point.longitude,
                                updated_at: position.updatedAt))
            .execute()
    }

    func watch(roundId: UUID) async throws -> (round: Round, course: Course?) {
        let row: PastRoundRow = try await client.from("rounds")
            .select("id, started_at, stakes, paid, course:courses(id, name, data), round_players(player:profiles(*)), scores(player_id, hole, strokes)")
            .eq("id", value: roundId.uuidString.lowercased())
            .single()
            .execute().value
        var round = Round(course: row.course.data, players: row.round_players.map(\.player.player))
        round.id = row.id
        round.date = row.started_at
        for score in row.scores {
            round.setStrokes(score.strokes, for: score.player_id.uuidString.lowercased(), hole: score.hole)
        }
        return (round, row.course.data)
    }

    /// Realtime for watchers: scores, positions and cheers in the round, and the round ending.
    func liveEvents(roundId: UUID) -> AsyncStream<LiveEvent> {
        let client = client
        let id = roundId.uuidString.lowercased()
        return AsyncStream { continuation in
            let task = Task {
                let players = (try? await self.watch(roundId: roundId).round.players) ?? []
                let byId = Dictionary(uniqueKeysWithValues: players.map { ($0.id, $0) })
                let channel = client.channel("live-\(id)")
                let scores = channel.postgresChange(AnyAction.self, schema: "public", table: "scores", filter: "round_id=eq.\(id)")
                let positions = channel.postgresChange(AnyAction.self, schema: "public", table: "live_positions", filter: "round_id=eq.\(id)")
                let cheers = channel.postgresChange(InsertAction.self, schema: "public", table: "live_cheers", filter: "round_id=eq.\(id)")
                let rounds = channel.postgresChange(UpdateAction.self, schema: "public", table: "rounds", filter: "id=eq.\(id)")
                await channel.subscribe()
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await change in scores {
                            switch change {
                            case .insert(let action):
                                if let row = try? action.decodeRecord(as: ScoreRow.self, decoder: Self.decoder) {
                                    continuation.yield(.score(playerId: row.player_id.uuidString.lowercased(), hole: row.hole, strokes: row.strokes))
                                }
                            case .update(let action):
                                if let row = try? action.decodeRecord(as: ScoreRow.self, decoder: Self.decoder) {
                                    continuation.yield(.score(playerId: row.player_id.uuidString.lowercased(), hole: row.hole, strokes: row.strokes))
                                }
                            case .delete:
                                break
                            }
                        }
                    }
                    group.addTask {
                        for await change in positions {
                            let record: PositionRow?
                            switch change {
                            case .insert(let action): record = try? action.decodeRecord(as: PositionRow.self, decoder: Self.decoder)
                            case .update(let action): record = try? action.decodeRecord(as: PositionRow.self, decoder: Self.decoder)
                            case .delete: record = nil
                            }
                            if let record, let player = record.player_id {
                                continuation.yield(.position(LivePosition(playerId: player.uuidString.lowercased(), hole: record.hole,
                                                                          point: Coordinate(record.lat, record.lon), updatedAt: record.updated_at)))
                            }
                        }
                    }
                    group.addTask {
                        for await change in cheers {
                            guard let row = try? change.decodeRecord(as: CheerRow.self, decoder: Self.decoder) else { continue }
                            let author = byId[row.author_id.uuidString.lowercased()]
                                ?? Player(id: row.author_id.uuidString.lowercased(), name: "Friend", avatar: "🙂")
                            continuation.yield(.cheer(LiveCheer(id: row.id, author: author, text: row.body, sentAt: row.sent_at)))
                        }
                    }
                    group.addTask {
                        for await change in rounds {
                            if let row = try? change.decodeRecord(as: LiveRoundRow.self, decoder: Self.decoder),
                               !row.live || row.finished_at != nil {
                                continuation.yield(.ended)
                            }
                        }
                    }
                }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func cheer(_ text: String, roundId: UUID) async throws {
        try await client.from("live_cheers").insert(CheerInsert(round_id: roundId, body: text)).execute()
    }

    /// The `livekit-token` edge function checks the golfer may stream or watch this round.
    func liveVideoAccess(roundId: UUID, publish: Bool) async throws -> LiveVideoAccess {
        try await client.functions.invoke("livekit-token",
                                          options: FunctionInvokeOptions(body: VideoTokenParams(round_id: roundId, publish: publish)))
    }

    // MARK: Rounds

    func startRound(_ round: Round, course: Course) async throws -> Round {
        // Courses are stored on first play so drops and challenge checks can use their holes.
        try await client.from("courses").upsert(CourseRow(id: course.id, name: course.name, data: course)).execute()
        try await client.from("rounds").insert(RoundInsert(id: round.id, course_id: course.id, stakes: round.stakes)).execute()
        let players = round.players.compactMap { UUID(uuidString: $0.id) }.map { RoundPlayerRow(round_id: round.id, player_id: $0) }
        try await client.from("round_players").insert(players).execute()
        return round
    }

    func saveScore(round: Round, playerId: String, hole: Int, strokes: Int?) async throws {
        guard let player = UUID(uuidString: playerId) else { return }
        if let strokes {
            try await client.from("scores")
                .upsert(ScoreRow(round_id: round.id, player_id: player, hole: hole, strokes: strokes))
                .execute()
        } else {
            try await client.from("scores").delete()
                .eq("round_id", value: round.id.uuidString.lowercased())
                .eq("player_id", value: playerId)
                .eq("hole", value: hole)
                .execute()
        }
    }

    func sendChat(_ message: ChatMessage, round: Round) async throws {
        try await client.from("chat_messages")
            .insert(ChatInsert(id: message.id, round_id: round.id, body: message.text))
            .execute()
    }

    /// Realtime: new and changed scores and new chat messages from everyone in the round.
    func roundEvents(_ round: Round) -> AsyncStream<RoundEvent> {
        let client = client
        let roundId = round.id.uuidString.lowercased()
        let players = Dictionary(uniqueKeysWithValues: round.players.map { ($0.id, $0) })
        return AsyncStream { continuation in
            let task = Task {
                let channel = client.channel("round-\(roundId)")
                let inserted = channel.postgresChange(InsertAction.self, schema: "public", table: "scores", filter: "round_id=eq.\(roundId)")
                let updated = channel.postgresChange(UpdateAction.self, schema: "public", table: "scores", filter: "round_id=eq.\(roundId)")
                let chats = channel.postgresChange(InsertAction.self, schema: "public", table: "chat_messages", filter: "round_id=eq.\(roundId)")
                await channel.subscribe()

                func yieldScore(_ row: ScoreRow) {
                    continuation.yield(.score(playerId: row.player_id.uuidString.lowercased(), hole: row.hole, strokes: row.strokes))
                }
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await change in inserted {
                            if let row = try? change.decodeRecord(as: ScoreRow.self, decoder: Self.decoder) { yieldScore(row) }
                        }
                    }
                    group.addTask {
                        for await change in updated {
                            if let row = try? change.decodeRecord(as: ScoreRow.self, decoder: Self.decoder) { yieldScore(row) }
                        }
                    }
                    group.addTask {
                        for await change in chats {
                            guard let row = try? change.decodeRecord(as: ChatRow.self, decoder: Self.decoder) else { continue }
                            let author = players[row.author_id.uuidString.lowercased()]
                                ?? Player(id: row.author_id.uuidString.lowercased(), name: "Golfer", avatar: "🏌️")
                            continuation.yield(.chat(ChatMessage(id: row.id, author: author, text: row.body, sentAt: row.sent_at)))
                        }
                    }
                }
                await client.removeChannel(channel)
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func finish(_ round: Round) async throws {
        try await client.from("rounds")
            .update(["finished_at": ISO8601DateFormatter().string(from: .now)])
            .eq("id", value: round.id.uuidString.lowercased())
            .execute()
    }

    func saveSideBets(_ round: Round) async throws {
        try await client.rpc("save_side_bets", params: SideBetsParams(p_round: round.id, p_stakes: round.stakes, p_paid: round.paid ?? []))
            .execute()
    }

    func pastRounds() async throws -> [Round] {
        let rows: [PastRoundRow] = try await client.from("rounds")
            .select("id, started_at, stakes, paid, course:courses(id, name, data), round_players(player:profiles(*)), scores(player_id, hole, strokes)")
            .not("finished_at", operator: .is, value: "null")
            .order("started_at", ascending: false)
            .limit(40)
            .execute().value
        return rows.map { row in
            var round = Round(course: row.course.data, players: row.round_players.map(\.player.player))
            round.id = row.id
            round.date = row.started_at
            round.isActive = false
            round.stakes = row.stakes
            round.paid = row.paid
            for score in row.scores {
                round.setStrokes(score.strokes, for: score.player_id.uuidString.lowercased(), hole: score.hole)
            }
            return round
        }
    }

    // MARK: Drops

    func drops(for course: Course) async throws -> [Drop] {
        let rows: [DropRow] = try await client.from("drops").select().eq("course_id", value: course.id).execute().value
        return rows.map(\.drop)
    }

    func visit(drop: Drop, round: Round, at point: Coordinate) async throws {
        guard let dropId = UUID(uuidString: drop.id) else { return }
        try await client.rpc("visit_drop", params: VisitParams(p_drop: dropId, p_round: round.id,
                                                              p_lat: point.latitude, p_lon: point.longitude)).execute()
    }

    func claim(drop: Drop, round: Round) async throws -> WonPrize {
        guard let dropId = UUID(uuidString: drop.id) else { throw ClaimError.outsideHole }
        let code: String = try await client.rpc("claim_drop", params: ClaimParams(p_drop: dropId, p_round: round.id)).execute().value
        var won = drop
        won.remaining = max(0, drop.remaining - 1)
        return WonPrize(drop: won, code: code)
    }

    func wallet() async throws -> [WonPrize] {
        let id = try await userId()
        let rows: [ClaimRow] = try await client.from("drop_claims")
            .select("code, claimed_at, redeemed_at, drop:drops(*)")
            .eq("user_id", value: id)
            .order("claimed_at", ascending: false)
            .execute().value
        return rows.map { WonPrize(drop: $0.drop.drop, code: $0.code, wonAt: $0.claimed_at, redeemed: $0.redeemed_at != nil) }
    }

    // MARK: Rows (column names match supabase/schema.sql)

    /// Postgres timestamps carry microseconds, which the default ISO 8601 parser rejects.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let trimmed = text.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: trimmed) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: trimmed) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date \(text)"))
        }
        return decoder
    }()
}

private struct ProfileRow: Decodable {
    var id: UUID
    var name: String
    var avatar: String
    var handicap: Double?
    var venmo: String?
    var cash_app: String?
    var home_course: String?
    var handle: String?

    var player: Player {
        Player(id: id.uuidString.lowercased(), name: name, avatar: avatar, handicap: handicap, venmo: venmo, cashApp: cash_app,
               homeCourse: home_course, handle: handle)
    }
}

private struct FriendRow: Decodable { var friend: ProfileRow }

/// A row of `feed_view`: the post, the author's card and the counts.
private struct FeedRow: Decodable {
    var id: UUID
    var author_id: UUID
    var kind: String
    var title: String
    var detail: String
    var posted_at: Date
    var audience: String
    var course_id: String?
    var course_name: String?
    var hole: Int?
    var video_url: String?
    var image_url: String?
    var round_id: UUID?
    var ref_post_id: UUID?
    var views: Int
    var author_name: String
    var author_avatar: String
    var author_handicap: Double?
    var author_home_course: String?
    var author_handle: String?
    var likes: Int
    var congrats: Int
    var liked_by_me: Bool
    var congrats_by_me: Bool
    var comment_count: Int

    var post: FeedPost {
        FeedPost(id: id,
                 author: Player(id: author_id.uuidString.lowercased(), name: author_name, avatar: author_avatar,
                                handicap: author_handicap, homeCourse: author_home_course, handle: author_handle),
                 kind: FeedPost.Kind(rawValue: kind) ?? .note, title: title, detail: detail, postedAt: posted_at,
                 likes: likes, likedByMe: liked_by_me, congrats: congrats, congratsByMe: congrats_by_me,
                 comments: comment_count, views: views, audience: FeedPost.Audience(rawValue: audience) ?? .friends,
                 courseId: course_id, courseName: course_name, hole: hole,
                 videoURL: video_url.flatMap(URL.init(string:)), imageURL: image_url.flatMap(URL.init(string:)),
                 roundId: round_id, refPostId: ref_post_id)
    }
}

private struct FeedInsert: Encodable {
    var id: UUID
    var kind: String
    var title: String
    var detail: String
    var audience: String
    var course_id: String?
    var course_name: String?
    var hole: Int?
    var video_url: String?
    var image_url: String?
    var round_id: UUID?
    var ref_post_id: UUID?

    init(_ post: FeedPost) {
        id = post.id
        kind = post.kind.rawValue
        title = post.title
        detail = post.detail
        audience = post.audience.rawValue
        course_id = post.courseId
        course_name = post.courseName
        hole = post.hole
        // Only uploaded clips (https) are shared; a clip still on the phone isn't.
        video_url = post.videoURL.flatMap { $0.scheme == "https" ? $0.absoluteString : nil }
        image_url = post.imageURL.flatMap { $0.scheme == "https" ? $0.absoluteString : nil }
        round_id = post.roundId
        ref_post_id = post.refPostId
    }
}

private struct ReactionRow: Encodable {
    var post_id: UUID
    var kind: String
}

private struct BlockRow: Encodable {
    var blocked_id: String
}

private struct ReportInsert: Encodable {
    var reason: String
    var user_id: String
    var post_id: UUID? = nil
    var comment_id: UUID? = nil
}

private struct CommentInsert: Encodable {
    var post_id: UUID
    var body: String
}

private struct CommentRow: Decodable {
    var id: UUID
    var body: String
    var posted_at: Date
    var author: ProfileRow

    var comment: FeedComment { FeedComment(id: id, author: author.player, text: body, postedAt: posted_at) }
}

private struct LiveParams: Encodable {
    var p_round: UUID
    var p_live: Bool
}

private struct PositionRow: Codable {
    var round_id: UUID
    var player_id: UUID?
    var hole: Int
    var lat: Double
    var lon: Double
    var updated_at: Date
}

private struct VideoTokenParams: Encodable {
    var round_id: UUID
    var publish: Bool
}

private struct CheerInsert: Encodable {
    var round_id: UUID
    var body: String
}

private struct CheerRow: Decodable {
    var id: UUID
    var author_id: UUID
    var body: String
    var sent_at: Date
}

private struct LiveRoundRow: Decodable {
    var id: UUID
    var created_by: UUID?
    var live: Bool
    var finished_at: Date?
}

private struct CourseRow: Encodable {
    var id: String
    var name: String
    var data: Course
}

private struct RoundInsert: Encodable {
    var id: UUID
    var course_id: String
    var stakes: Stakes?
}

private struct SideBetsParams: Encodable {
    var p_round: UUID
    var p_stakes: Stakes?
    var p_paid: [String]
}

private struct RoundPlayerRow: Encodable {
    var round_id: UUID
    var player_id: UUID
}

private struct ScoreRow: Codable {
    var round_id: UUID
    var player_id: UUID
    var hole: Int
    var strokes: Int
}

private struct ChatInsert: Encodable {
    var id: UUID
    var round_id: UUID
    var body: String
}

private struct ChatRow: Decodable {
    var id: UUID
    var author_id: UUID
    var body: String
    var sent_at: Date
}

private struct PastRoundRow: Decodable {
    struct CourseData: Decodable { var data: Course }
    struct PlayerRow: Decodable { var player: ProfileRow }
    struct Score: Decodable { var player_id: UUID; var hole: Int; var strokes: Int }

    var id: UUID
    var started_at: Date
    var course: CourseData
    var round_players: [PlayerRow]
    var scores: [Score]
    var stakes: Stakes?
    var paid: [String]?
}

private struct DropRow: Decodable {
    var id: UUID
    var brand: String
    var prize: String
    var detail: String
    var course_id: String
    var hole: Int
    var lat: Double
    var lon: Double
    var radius_m: Double
    var challenge: String
    var remaining: Int
    var expires_at: Date
    var headline: String?
    var image_url: String?
    var claim_url: String?

    var drop: Drop {
        Drop(id: id.uuidString.lowercased(), brand: brand, prize: prize, detail: detail, courseId: course_id,
             holeNumber: hole, center: Coordinate(lat, lon), radiusMeters: radius_m,
             challenge: Drop.Challenge(rawValue: challenge) ?? Drop.Challenge.none, remaining: remaining, expires: expires_at,
             headline: headline, imageURL: image_url.flatMap(URL.init(string:)), claimURL: claim_url.flatMap(URL.init(string:)))
    }
}

private struct ClaimRow: Decodable {
    var code: String
    var claimed_at: Date
    var redeemed_at: Date?
    var drop: DropRow
}

private struct VisitParams: Encodable {
    var p_drop: UUID
    var p_round: UUID
    var p_lat: Double
    var p_lon: Double
}

private struct ClaimParams: Encodable {
    var p_drop: UUID
    var p_round: UUID
}
#endif
