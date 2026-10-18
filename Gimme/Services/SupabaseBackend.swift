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
        return rows.map(\.friend.player).sorted { $0.name < $1.name }
    }

    func addFriend(handle: String) async throws {
        let clean = handle.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")).lowercased()
        try await client.rpc("add_friend", params: ["p_handle": clean]).execute()
    }

    func feed() async throws -> [FeedPost] {
        let rows: [FeedRow] = try await client.from("feed_posts")
            .select("*, author:profiles(*)")
            .order("posted_at", ascending: false)
            .limit(50)
            .execute().value
        return rows.map {
            FeedPost(id: $0.id, author: $0.author.player, kind: FeedPost.Kind(rawValue: $0.kind) ?? .note,
                     title: $0.title, detail: $0.detail, postedAt: $0.posted_at)
        }
    }

    func publish(_ post: FeedPost) async throws {
        try await client.from("feed_posts")
            .insert(FeedInsert(id: post.id, kind: post.kind.rawValue, title: post.title, detail: post.detail))
            .execute()
    }

    // MARK: Rounds

    func startRound(_ round: Round, course: Course) async throws -> Round {
        // Courses are stored on first play so drops and challenge checks can use their holes.
        try await client.from("courses").upsert(CourseRow(id: course.id, name: course.name, data: course)).execute()
        try await client.from("rounds").insert(RoundInsert(id: round.id, course_id: course.id)).execute()
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

    func pastRounds() async throws -> [Round] {
        let rows: [PastRoundRow] = try await client.from("rounds")
            .select("id, started_at, course:courses(id, name, data), round_players(player:profiles(*)), scores(player_id, hole, strokes)")
            .not("finished_at", operator: .is, value: "null")
            .order("started_at", ascending: false)
            .limit(40)
            .execute().value
        return rows.map { row in
            var round = Round(course: row.course.data, players: row.round_players.map(\.player.player))
            round.id = row.id
            round.date = row.started_at
            round.isActive = false
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

    var player: Player { Player(id: id.uuidString.lowercased(), name: name, avatar: avatar, handicap: handicap) }
}

private struct FriendRow: Decodable { var friend: ProfileRow }

private struct FeedRow: Decodable {
    var id: UUID
    var kind: String
    var title: String
    var detail: String
    var posted_at: Date
    var author: ProfileRow
}

private struct FeedInsert: Encodable {
    var id: UUID
    var kind: String
    var title: String
    var detail: String
}

private struct CourseRow: Encodable {
    var id: String
    var name: String
    var data: Course
}

private struct RoundInsert: Encodable {
    var id: UUID
    var course_id: String
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

    var drop: Drop {
        Drop(id: id.uuidString.lowercased(), brand: brand, prize: prize, detail: detail, courseId: course_id,
             holeNumber: hole, center: Coordinate(lat, lon), radiusMeters: radius_m,
             challenge: Drop.Challenge(rawValue: challenge) ?? Drop.Challenge.none, remaining: remaining, expires: expires_at)
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
