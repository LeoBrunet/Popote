import Foundation
import HealthKit
import Observation

/// Writes logged meals to Apple Health and reads energy burned + weight for the daily targets.
@MainActor
@Observable
final class HealthService {
    private let store = HKHealthStore()
    var connected = UserDefaults.standard.bool(forKey: "healthConnected")
    var activeToday: Double = 0
    var basalPerDay: Double?
    var bodyMass: Double?
    /// Today's Apple Watch (or other) workouts, for the real training calories.
    var todayWorkouts: [HealthWorkout] = []
    /// Usual non-workout active energy per day (14-day average).
    var movementPerDay: Double?
    /// Weigh-ins over the last 5 weeks, oldest first.
    var weights: [(date: Date, kg: Double)] = []
    /// Resting + active energy per past day (last 21 days), keyed by start of day.
    var burnByDay: [Date: Double] = [:]

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private let writeTypes: Set<HKSampleType> = [
        HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal),
    ]
    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned), HKQuantityType(.basalEnergyBurned), HKQuantityType(.bodyMass),
        HKQuantityType(.dietaryEnergyConsumed), HKObjectType.workoutType(),
    ]

    func connect() async {
        guard available else { return }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            connected = true
            UserDefaults.standard.set(true, forKey: "healthConnected")
            await refresh()
        } catch {
            connected = false
        }
    }

    func refresh() async {
        guard connected else { return }
        // Workouts were added to the read types later: ask once more (only the new type is shown).
        if !UserDefaults.standard.bool(forKey: "healthWorkoutsAsked") {
            try? await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            UserDefaults.standard.set(true, forKey: "healthWorkoutsAsked")
        }
        let startOfDay = Calendar.current.startOfDay(for: .now)
        activeToday = await sum(.activeEnergyBurned, from: startOfDay, to: .now) ?? 0
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: startOfDay)!
        if let basal = await sum(.basalEnergyBurned, from: weekAgo, to: startOfDay), basal > 0 { basalPerDay = basal / 7 }
        bodyMass = await latest(.bodyMass, unit: .gramUnit(with: .kilo))
        await refreshHistory(startOfDay: startOfDay)
    }

    private func refreshHistory(startOfDay: Date) async {
        let calendar = Calendar.current
        todayWorkouts = await workouts(from: startOfDay, to: .now)

        // Everyday movement: active energy minus workouts, over the last 14 full days.
        let twoWeeksAgo = calendar.date(byAdding: .day, value: -14, to: startOfDay)!
        let active = await dailySums(.activeEnergyBurned, from: twoWeeksAgo, to: startOfDay)
        let pastWorkouts = await workouts(from: twoWeeksAgo, to: startOfDay)
        let days = active.filter { $0.value > 0 }
        if days.count >= 5 {
            let workoutEnergy = pastWorkouts.filter { days[calendar.startOfDay(for: $0.start)] != nil }.reduce(0) { $0 + $1.kcal }
            movementPerDay = max(days.values.reduce(0, +) - workoutEnergy, 0) / Double(days.count)
        }

        // History for learning the real maintenance.
        let threeWeeksAgo = calendar.date(byAdding: .day, value: -21, to: startOfDay)!
        let basal = await dailySums(.basalEnergyBurned, from: threeWeeksAgo, to: startOfDay)
        let activeLong = await dailySums(.activeEnergyBurned, from: threeWeeksAgo, to: startOfDay)
        burnByDay = basal.filter { $0.value > 0 }.reduce(into: [:]) { result, item in
            result[item.key] = item.value + (activeLong[item.key] ?? 0)
        }
        let fiveWeeksAgo = calendar.date(byAdding: .day, value: -35, to: startOfDay)!
        weights = await samples(.bodyMass, unit: .gramUnit(with: .kilo), from: fiveWeeksAgo)
    }

    // MARK: Meals

    /// Saves a meal as a food correlation; returns its UUID to delete it later.
    func save(_ entry: JournalEntry) async -> String? {
        guard connected else { return nil }
        let date = entry.date
        let samples: [HKQuantitySample] = [
            (HKQuantityType(.dietaryEnergyConsumed), HKQuantity(unit: .kilocalorie(), doubleValue: entry.kcal)),
            (HKQuantityType(.dietaryProtein), HKQuantity(unit: .gram(), doubleValue: entry.protein)),
            (HKQuantityType(.dietaryCarbohydrates), HKQuantity(unit: .gram(), doubleValue: entry.carbs)),
            (HKQuantityType(.dietaryFatTotal), HKQuantity(unit: .gram(), doubleValue: entry.fat)),
        ].map { HKQuantitySample(type: $0.0, quantity: $0.1, start: date, end: date) }
        let food = HKCorrelation(type: HKCorrelationType(.food), start: date, end: date, objects: Set(samples),
                                 metadata: [HKMetadataKeyFoodType: entry.title, "PopoteEntryID": entry.id.uuidString])
        do {
            try await store.save(food)
            return food.uuid.uuidString
        } catch {
            return nil
        }
    }

    func delete(healthUUID: String) async {
        guard connected, let uuid = UUID(uuidString: healthUUID) else { return }
        let predicate = HKQuery.predicateForObject(with: uuid)
        let correlations: [HKCorrelation] = await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(type: HKCorrelationType(.food), predicate: predicate, samplePredicates: nil) { _, results, _ in
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
        for correlation in correlations {
            try? await store.delete(Array(correlation.objects) + [correlation])
        }
    }

    // MARK: Queries

    private func sum(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date) async -> Double? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
            let query = HKStatisticsQuery(quantityType: HKQuantityType(id), quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()))
            }
            store.execute(query)
        }
    }

    private func dailySums(_ id: HKQuantityTypeIdentifier, from start: Date, to end: Date) async -> [Date: Double] {
        await withCheckedContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(id), quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum, anchorDate: start, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, _ in
                var result: [Date: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let value = stats.sumQuantity()?.doubleValue(for: .kilocalorie()) { result[stats.startDate] = value }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private func samples(_ id: HKQuantityTypeIdentifier, unit: HKUnit, from start: Date) async -> [(date: Date, kg: Double)] {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: HKQuery.predicateForSamples(withStart: start, end: .now),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                let values = (samples as? [HKQuantitySample] ?? []).map { (date: $0.endDate, kg: $0.quantity.doubleValue(for: unit)) }
                continuation.resume(returning: values)
            }
            store.execute(query)
        }
    }

    private func workouts(from start: Date, to end: Date) async -> [HealthWorkout] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: .workoutType(), predicate: HKQuery.predicateForSamples(withStart: start, end: end),
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let workouts = (samples as? [HKWorkout] ?? []).map { workout in
                    HealthWorkout(start: workout.startDate, minutes: workout.duration / 60, sport: HealthWorkout.sport(workout.workoutActivityType),
                                  kcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
                }
                continuation.resume(returning: workouts)
            }
            store.execute(query)
        }
    }

    private func latest(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async -> Double? {
        await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}

/// A workout read from Health, mapped to Coach's sports.
struct HealthWorkout: Hashable {
    let start: Date
    let minutes: Double
    let sport: String      // course, velo, natation, muscu, autre
    let kcal: Double

    static func sport(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "course"
        case .cycling: "velo"
        case .swimming: "natation"
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining: "muscu"
        default: "autre"
        }
    }
}
