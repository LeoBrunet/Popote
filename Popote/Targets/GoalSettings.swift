import Foundation

/// Weight goal and how it follows the Coach plan. Stored as JSON in @AppStorage("goal").
struct GoalSettings: Codable, Equatable, RawRepresentable {
    enum Kind: String, Codable, CaseIterable { case lose, maintain, gain }

    var kind = Kind.maintain
    /// kg per week, always positive (the direction comes from `kind`).
    var rate = 0.25
    var targetWeight: Double?
    var adaptToPlan = true
    var noDeficitOnKeyDays = true
    var maintainRaceWeek = true
    var proteinPerKg = UserDefaults.standard.object(forKey: "proteinPerKg") as? Double ?? 1.8

    static let loseRates = [0.25, 0.5, 0.75]
    static let gainRates = [0.25, 0.5]

    init() {}

    // Explicit Codable: the default one for a String RawRepresentable would encode `rawValue`, which encodes self.
    private enum CodingKeys: String, CodingKey {
        case kind, rate, targetWeight, adaptToPlan, noDeficitOnKeyDays, maintainRaceWeek, proteinPerKg
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .maintain
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 0.25
        targetWeight = try c.decodeIfPresent(Double.self, forKey: .targetWeight)
        adaptToPlan = try c.decodeIfPresent(Bool.self, forKey: .adaptToPlan) ?? true
        noDeficitOnKeyDays = try c.decodeIfPresent(Bool.self, forKey: .noDeficitOnKeyDays) ?? true
        maintainRaceWeek = try c.decodeIfPresent(Bool.self, forKey: .maintainRaceWeek) ?? true
        proteinPerKg = try c.decodeIfPresent(Double.self, forKey: .proteinPerKg) ?? 1.8
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(rate, forKey: .rate)
        try c.encodeIfPresent(targetWeight, forKey: .targetWeight)
        try c.encode(adaptToPlan, forKey: .adaptToPlan)
        try c.encode(noDeficitOnKeyDays, forKey: .noDeficitOnKeyDays)
        try c.encode(maintainRaceWeek, forKey: .maintainRaceWeek)
        try c.encode(proteinPerKg, forKey: .proteinPerKg)
    }

    init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8), let value = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = value
    }

    var rawValue: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static var current: GoalSettings {
        UserDefaults.standard.string(forKey: "goal").flatMap(GoalSettings.init(rawValue:)) ?? GoalSettings()
    }

    /// "Lose 0.25 kg/week", "Maintain"…
    var title: String {
        switch kind {
        case .lose: String(localized: "Lose \(rate.formatted()) kg/week")
        case .maintain: String(localized: "Maintain")
        case .gain: String(localized: "Gain \(rate.formatted()) kg/week")
        }
    }

    /// Signed kg per week.
    var weeklyChange: Double {
        switch kind {
        case .lose: -rate
        case .maintain: 0
        case .gain: rate
        }
    }
}

/// What the weekly check learned about the real expenditure (stored in UserDefaults).
struct LearnedMaintenance: Codable, Equatable {
    /// kcal/day added to every target (real expenditure − formula).
    var correction: Double
    /// Measured weight change, kg/week (negative = losing).
    var measuredRate: Double
    var days: Int
    var updatedAt: Date

    static var current: LearnedMaintenance? {
        UserDefaults.standard.data(forKey: "learnedMaintenance").flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(self), forKey: "learnedMaintenance")
    }
}
