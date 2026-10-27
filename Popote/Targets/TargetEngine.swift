import Foundation
import SwiftData
import SwiftUI

/// Kind of training day, from the Coach plan. Drives the carbs and how much of the weekly deficit lands on it.
enum DayKind {
    case rest, easy, key, long

    var label: LocalizedStringKey {
        switch self {
        case .rest: "Rest day"
        case .easy: "Easy day"
        case .key: "Key session"
        case .long: "Long day"
        }
    }

    var color: Color {
        switch self {
        case .rest: .secondary
        case .easy: Theme.herb
        case .key: Theme.accent
        case .long: Theme.carbs
        }
    }

    /// Share of a weekly deficit (gain uses `surplusWeight`).
    var deficitWeight: Double {
        switch self {
        case .rest: 1.5
        case .easy: 1
        case .key: 1
        case .long: 0.5
        }
    }

    var surplusWeight: Double {
        switch self {
        case .rest: 0.7
        case .easy: 1
        case .key, .long: 1.3
        }
    }
}

/// One session counted in a day's target: planned by Coach (estimated) or recorded in Health (real).
struct TrainingItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let sport: String
    let minutes: Double
    let kcal: Double
    let real: Bool

    var icon: String {
        switch sport {
        case "course": "figure.run"
        case "velo": "figure.outdoor.cycle"
        case "natation": "figure.pool.swim"
        case "muscu": "figure.strengthtraining.traditional"
        default: "figure.mixed.cardio"
        }
    }
}

/// Why the goal adjustment is what it is today.
enum AdjustReason {
    case maintain, keyDay, raceWeek, reached, flat, rest, easy, long, gain

    var text: LocalizedStringKey {
        switch self {
        case .maintain: "Maintenance"
        case .keyDay: "No deficit on a key session day"
        case .raceWeek: "Race week: maintenance"
        case .reached: "Target weight reached: maintenance"
        case .flat: "Same every day"
        case .rest: "Rest day: larger deficit"
        case .easy: "Moderate deficit"
        case .long: "Smaller deficit: long session"
        case .gain: "Surplus, larger on training days"
        }
    }
}

struct DayPlan: Identifiable {
    var id: Date { date }
    let date: Date
    let kind: DayKind
    let trainings: [TrainingItem]
    let resting: Double
    let movement: Double
    let correction: Double
    let adjust: Double
    let adjustReason: AdjustReason
    let protein: Double
    let carbs: Double
    let fat: Double
    let carbsPerKg: Double
    let proteinPerKg: Double
    let fromHealth: Bool

    var training: Double { trainings.reduce(0) { $0 + $1.kcal } }
    var kcal: Double { resting + movement + training + correction + adjust }
    var isToday: Bool { Calendar.current.isDateInToday(date) }
}

/// Today's targets as plain numbers (used where only the totals matter, e.g. Claude's context).
struct DailyTargets {
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double

    @MainActor
    init(health: HealthService) {
        let plan = TargetEngine(health: health).plan(for: .now)
        kcal = plan.kcal
        protein = plan.protein
        carbs = plan.carbs
        fat = plan.fat
    }
}

/// Daily target = resting + everyday movement + training (planned by Coach, then real) + learned correction ± goal.
/// The weekly deficit or surplus is spread over the week by kind of day.
@MainActor
struct TargetEngine {
    let health: HealthService
    var goal = GoalSettings.current
    var coach = CoachPlan.load()
    var learned = LearnedMaintenance.current

    var weight: Double { health.bodyMass ?? (UserDefaults.standard.object(forKey: "bodyMass") as? Double ?? 70) }

    private var base: (resting: Double, movement: Double, fromHealth: Bool) {
        if let basal = health.basalPerDay { return (basal, health.movementPerDay ?? 0, true) }
        // Without Health, the base target in Settings covers resting energy and daily life.
        return (UserDefaults.standard.object(forKey: "baseKcal") as? Double ?? 2200, 0, false)
    }

    func plan(for date: Date) -> DayPlan {
        let day = Calendar.current.startOfDay(for: date)
        return week(of: day).first { Calendar.current.isDate($0.date, inSameDayAs: day) }!
    }

    /// Monday → Sunday around `date`.
    func week(of date: Date) -> [DayPlan] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let monday = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let days = (0..<7).map { Calendar.current.date(byAdding: .day, value: $0, to: monday)! }
        let raw = days.map { day -> (date: Date, kind: DayKind, trainings: [TrainingItem]) in
            let trainings = trainings(on: day)
            return (day, kind(of: day, trainings), trainings)
        }
        let base = base
        let correction = learned?.correction ?? 0
        let weeklyTraining = raw.reduce(0) { $0 + $1.trainings.reduce(0) { $0 + $1.kcal } } / 7

        // Weekly deficit/surplus and each day's share of it.
        let weekly = abs(goal.weeklyChange) * 7700
        let weights = raw.map { goal.kind == .gain ? $0.kind.surplusWeight : (goal.noDeficitOnKeyDays && $0.kind == .key ? 0 : $0.kind.deficitWeight) }
        let totalWeight = weights.reduce(0, +)

        return raw.enumerated().map { index, day in
            var trainings = day.trainings
            if !goal.adaptToPlan {
                // Flat target: the week's training spread evenly.
                trainings = weeklyTraining > 0 ? [TrainingItem(title: String(localized: "Training (weekly average)"), sport: "autre", minutes: 0, kcal: weeklyTraining, real: false)] : []
            }
            let maintenance = base.resting + base.movement + trainings.reduce(0) { $0 + $1.kcal } + correction

            var adjust = 0.0
            var reason = AdjustReason.maintain
            if goal.kind != .maintain {
                if goal.kind == .lose, let target = goal.targetWeight, weight <= target {
                    reason = .reached
                } else if goal.kind == .lose, goal.maintainRaceWeek, let race = coach?.raceDate,
                          let gap = Calendar.current.dateComponents([.day], from: day.date, to: race).day, (0...6).contains(gap) {
                    reason = .raceWeek
                } else if !goal.adaptToPlan {
                    adjust = weekly / 7
                    reason = .flat
                } else {
                    adjust = totalWeight > 0 ? weekly * weights[index] / totalWeight : weekly / 7
                    reason = switch (goal.kind, day.kind) {
                    case (.gain, _): .gain
                    case (_, .key): goal.noDeficitOnKeyDays ? .keyDay : .easy
                    case (_, .rest): .rest
                    case (_, .long): .long
                    default: .easy
                    }
                }
                adjust = goal.kind == .lose ? -min(adjust, maintenance * 0.2) : min(adjust, maintenance * 0.15)
            }

            let kcal = maintenance + adjust
            let carbsPerKg = goal.adaptToPlan ? carbsPerKg(day.kind, trainings) : 4.5
            let protein = weight * goal.proteinPerKg
            var carbs = weight * carbsPerKg
            var fat = (kcal - protein * 4 - carbs * 4) / 9
            let fatFloor = weight * 0.8
            if fat < fatFloor {
                fat = fatFloor
                carbs = max((kcal - protein * 4 - fat * 9) / 4, 0)
            }
            return DayPlan(date: day.date, kind: goal.adaptToPlan ? day.kind : .easy, trainings: trainings,
                           resting: base.resting, movement: base.movement, correction: correction,
                           adjust: adjust, adjustReason: reason, protein: protein, carbs: carbs, fat: fat,
                           carbsPerKg: carbs / weight, proteinPerKg: goal.proteinPerKg, fromHealth: base.fromHealth)
        }
    }

    // MARK: Training

    /// Planned sessions, replaced by the real workout once Health has it (today only).
    private func trainings(on day: Date) -> [TrainingItem] {
        let sessions = coach?.sessions(on: day) ?? []
        guard Calendar.current.isDateInToday(day) else { return sessions.map(estimate) }
        var real = health.todayWorkouts
        var items: [TrainingItem] = []
        for session in sessions {
            if let index = real.firstIndex(where: { $0.sport == session.sport }) {
                let workout = real.remove(at: index)
                items.append(TrainingItem(title: session.title, sport: session.sport, minutes: workout.minutes, kcal: workout.kcal, real: true))
            } else {
                items.append(estimate(session))
            }
        }
        items += real.map { TrainingItem(title: Self.sportName($0.sport), sport: $0.sport, minutes: $0.minutes, kcal: $0.kcal, real: true) }
        return items
    }

    /// Active calories for a planned session: minutes per zone × (MET − 1) × weight.
    private func estimate(_ session: CoachPlan.Session) -> TrainingItem {
        let duration = Double(session.durationMin)
        var minutes: [Double]
        if let zones = session.zoneMinutes, zones.count == 5, zones.reduce(0, +) > 0 {
            let scale = max(duration, zones.reduce(0, +)) / zones.reduce(0, +)
            minutes = zones.map { $0 * scale }
        } else {
            minutes = [0, 0, 0, 0, 0]
            let zone = switch session.load?.lowercased() {
            case "faible": 1
            case "élevée", "elevee": 3
            default: 2
            }
            minutes[zone] = duration
        }
        let mets = Self.mets[session.sport] ?? [4, 5, 6, 7, 8]
        let kcal = zip(minutes, mets).reduce(0) { $0 + $1.0 / 60 * ($1.1 - 1) * weight }
        return TrainingItem(title: session.title, sport: session.sport, minutes: duration, kcal: kcal, real: false)
    }

    private static let mets: [String: [Double]] = [
        "course": [7.5, 9.5, 11, 12.5, 14],
        "velo": [5.5, 7.5, 9.5, 11, 12.5],
        "natation": [6, 7.5, 9, 10, 11],
        "muscu": [3.5, 4.5, 5.5, 6, 6],
    ]

    private func kind(of day: Date, _ trainings: [TrainingItem]) -> DayKind {
        guard !trainings.isEmpty else { return .rest }
        let sessions = coach?.sessions(on: day) ?? []
        let hard = sessions.contains { session in
            let load = session.load?.lowercased()
            let intense = (session.zoneMinutes?.count == 5) ? session.zoneMinutes![3] + session.zoneMinutes![4] : 0
            return load == "élevée" || load == "elevee" || intense >= 8
        }
        if hard { return .key }
        let minutes = trainings.reduce(0) { $0 + $1.minutes }
        let long = trainings.contains { $0.sport == "course" } ? minutes >= 75 : minutes >= 90
        return long ? .long : .easy
    }

    private func carbsPerKg(_ kind: DayKind, _ trainings: [TrainingItem]) -> Double {
        switch kind {
        case .rest: 3
        case .easy: 4.5
        case .key: 5.5
        case .long: trainings.reduce(0) { $0 + $1.minutes } >= 150 ? 7.5 : 6
        }
    }

    static func sportName(_ sport: String) -> String {
        switch sport {
        case "course": String(localized: "Run")
        case "velo": String(localized: "Ride")
        case "natation": String(localized: "Swim")
        case "muscu": String(localized: "Strength")
        default: String(localized: "Workout")
        }
    }
}

/// Once a week, compares the weight trend with what was eaten and burned, and corrects the targets.
enum MaintenanceLearner {
    @MainActor
    static func update(context: ModelContext, health: HealthService) {
        if let last = LearnedMaintenance.current, Date().timeIntervalSince(last.updatedAt) < 6 * 86_400 { return }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -21, to: today)!
        guard let entries = try? context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date >= start && $0.date < today })) else { return }
        let intake = entries.reduce(into: [Date: Double]()) { $0[calendar.startOfDay(for: $1.date), default: 0] += $1.kcal }
        // Only days that look fully logged.
        let days = intake.filter { $0.value >= 1000 && health.burnByDay[$0.key] != nil }
        let weights = health.weights.filter { $0.date >= start }
        guard days.count >= 10, weights.count >= 4,
              let first = weights.first?.date, let last = weights.last?.date, last.timeIntervalSince(first) >= 10 * 86_400 else { return }

        // Least-squares slope of weight over time, kg/day.
        let xs = weights.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = weights.map(\.kg)
        let meanX = xs.reduce(0, +) / Double(xs.count), meanY = ys.reduce(0, +) / Double(ys.count)
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) } / max(xs.reduce(0) { $0 + pow($1 - meanX, 2) }, 1)

        let averageIntake = days.values.reduce(0, +) / Double(days.count)
        let averageBurn = days.keys.reduce(0) { $0 + health.burnByDay[$1]! } / Double(days.count)
        let real = averageIntake - slope * 7700
        let measured = min(max(real - averageBurn, -600), 600)
        let previous = LearnedMaintenance.current?.correction ?? 0
        LearnedMaintenance(correction: (previous + measured) / 2, measuredRate: slope * 7, days: days.count, updatedAt: .now).save()
    }
}
