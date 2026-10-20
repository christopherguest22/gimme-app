import Foundation

/// A round the golfer has booked. Home shows it until the round starts or the time passes.
struct TeeTime: Codable, Hashable {
    var courseId: String
    var courseName: String
    var date: Date

    /// Still worth showing: from now until a few hours after the tee time.
    var isUpcoming: Bool { date > Date.now.addingTimeInterval(-4 * 3600) }

    private static let key = "gimme.teeTime"

    static var saved: TeeTime? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TeeTime.self, from: data)
    }

    static func save(_ teeTime: TeeTime?) {
        if let teeTime, let data = try? JSONEncoder().encode(teeTime) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
