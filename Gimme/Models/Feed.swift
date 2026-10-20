import Foundation

/// A post in the Community feed: a video from a hole, a prize won, a finished round, a note,
/// a golfer reaching a hole where a clip is trending, or a round going live.
struct FeedPost: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case round, drop, note, clip, trending, live }
    /// Clips can be public like TikTok; everything else stays with friends.
    enum Audience: String, Codable { case everyone, friends }

    var id = UUID()
    var author: Player
    var kind: Kind
    var title: String
    var detail: String
    var postedAt = Date()
    var likes = 0
    var likedByMe = false
    /// LinkedIn-style "Congrats" on prizes and rounds.
    var congrats = 0
    var congratsByMe = false
    var comments = 0
    var views = 0
    var audience: Audience = .friends
    /// Where it happened: the hole tag on the post, and how trending clips are found for a hole.
    var courseId: String? = nil
    var courseName: String? = nil
    var hole: Int? = nil
    var videoURL: URL? = nil
    /// Prize photo on drop posts.
    var imageURL: URL? = nil
    /// The round being streamed, on live posts.
    var roundId: UUID? = nil
    /// The trending clip a trending post points to.
    var refPostId: UUID? = nil

    var icon: String {
        switch kind {
        case .round: "flag.fill"
        case .drop: "gift.fill"
        case .note: "text.bubble.fill"
        case .clip: "video.fill"
        case .trending: "flame.fill"
        case .live: "dot.radiowaves.left.and.right"
        }
    }

    /// "#17 · The Ocean Course"
    var holeTag: String? {
        guard let hole, let courseName else { return nil }
        return "#\(hole) · \(courseName)"
    }

    /// How hot a post is: likes, comments and views, fading over a couple of weeks so new
    /// clips can catch up with old favorites.
    var trendScore: Double {
        let days = max(Date.now.timeIntervalSince(postedAt) / 86_400, 0)
        return Double(likes * 3 + comments * 4 + congrats * 2 + views) / pow(days + 2, 1.2)
    }
}

struct FeedComment: Identifiable, Codable, Hashable {
    var id = UUID()
    var author: Player
    var text: String
    var postedAt = Date()
}

enum Reaction: String, Codable { case like, congrats }

/// Picks the clip to show a golfer who has just reached a hole: the hottest clip someone else
/// posted on that hole in the last 60 days, if it has any traction at all.
enum Trending {
    static let window: TimeInterval = 60 * 86_400

    static func clip(on hole: Int, courseId: String, in posts: [FeedPost], excluding me: String) -> FeedPost? {
        posts
            .filter { $0.kind == .clip && $0.courseId == courseId && $0.hole == hole && $0.author.id != me }
            .filter { Date.now.timeIntervalSince($0.postedAt) < window && $0.likes + $0.views + $0.comments > 0 }
            .max { $0.trendScore < $1.trendScore }
    }

    /// For You: the hottest posts first, with live rounds pinned on top.
    static func forYou(_ posts: [FeedPost]) -> [FeedPost] {
        posts.sorted {
            if ($0.kind == .live) != ($1.kind == .live) { return $0.kind == .live }
            return $0.trendScore > $1.trendScore
        }
    }
}

/// Where a golfer streaming their round is standing right now.
struct LivePosition: Codable, Hashable {
    var playerId: String
    var hole: Int
    var point: Coordinate
    var updatedAt = Date()
}

/// A message from someone watching a round live.
struct LiveCheer: Identifiable, Codable, Hashable {
    var id = UUID()
    var author: Player
    var text: String
    var sentAt = Date()
}

/// A LiveKit server and an access token for one round's camera stream.
struct LiveVideoAccess: Decodable, Hashable {
    var url: URL
    var token: String
}

enum LiveVideoError: LocalizedError {
    case notSetUp
    var errorDescription: String? { "Live video isn't set up yet." }
}

/// What changes while a friend watches a round live.
enum LiveEvent {
    case score(playerId: String, hole: Int, strokes: Int?)
    case position(LivePosition)
    case cheer(LiveCheer)
    case clip(FeedPost)
    case ended
}

extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}
