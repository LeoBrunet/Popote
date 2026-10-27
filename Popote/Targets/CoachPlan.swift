import Foundation

/// The training plan written by the Coach app into the shared App Group (Coach's `PlanShare`; keep both in sync).
struct CoachPlan: Codable {
    static let group = "group.com.leobrunet.shared"
    static let fileName = "coach-plan.json"

    struct Goal: Codable {
        var title: String
        var date: String?
    }

    struct Session: Codable, Hashable {
        var date: String
        var sport: String           // course, velo, natation, muscu, repos
        var title: String
        var durationMin: Int
        var load: String?
        var zoneMinutes: [Double]?
        var done: Bool
    }

    var version: Int
    var updatedAt: Date
    var goal: Goal?
    var sessions: [Session]

    func sessions(on date: Date) -> [Session] {
        let key = DayKey.string(date)
        return sessions.filter { $0.date == key && $0.sport != "repos" }
    }

    /// Race day from Coach's goal, if any.
    var raceDate: Date? { goal?.date.flatMap(DayKey.date) }

    private static var cache: (modified: Date, plan: CoachPlan)?

    /// Reads the file (cached until it changes). Nil when Coach isn't installed or hasn't synced yet.
    static func load() -> CoachPlan? {
        guard let folder = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { return nil }
        let url = folder.appending(path: fileName)
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: url.path()))?[.modificationDate] as? Date else { return nil }
        if let cache, cache.modified == modified { return cache.plan }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let plan = try? decoder.decode(CoachPlan.self, from: data) else { return nil }
        cache = (modified, plan)
        return plan
    }
}

/// "yyyy-MM-dd" in the local time zone, as Coach writes dates.
enum DayKey {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ string: String) -> Date? { formatter.date(from: string) }
}
