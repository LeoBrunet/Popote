import SwiftUI

/// Weight goal (lose / maintain / gain + pace), how it follows the Coach plan, protein, and what Popote learned.
struct GoalView: View {
    @Environment(HealthService.self) private var health
    @AppStorage("goal") private var goal = GoalSettings()

    private var engine: TargetEngine { TargetEngine(health: health, goal: goal) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                goalPicker
                if goal.kind != .maintain { projection }
                coachSection
                proteinSection
                LearnedMaintenanceCard(weights: health.weights, learned: LearnedMaintenance.current, goal: goal)
            }
            .padding(DS.Spacing.m)
        }
        .background(Theme.background)
        .navigationTitle("My goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Goal

    private var goalPicker: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.m) {
            Text("Your goal").font(Theme.titleFont)
            HStack(spacing: DS.Spacing.xs) {
                kindCard(.lose, "Lose", "arrow.down.right")
                kindCard(.maintain, "Maintain", "equal")
                kindCard(.gain, "Gain", "arrow.up.right")
            }
            if goal.kind != .maintain {
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Pace").font(.headline)
                    HStack(spacing: 6) {
                        ForEach(goal.kind == .lose ? GoalSettings.loseRates : GoalSettings.gainRates, id: \.self) { rate in
                            Button { goal.rate = rate } label: {
                                Chip(text: "\(goal.kind == .lose ? "−" : "+")\(rate.formatted()) kg/week", selected: goal.rate == rate)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text(paceText).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func kindCard(_ kind: GoalSettings.Kind, _ title: LocalizedStringKey, _ icon: String) -> some View {
        let selected = goal.kind == kind
        return Button {
            goal.kind = kind
            let rates = kind == .lose ? GoalSettings.loseRates : GoalSettings.gainRates
            if !rates.contains(goal.rate) { goal.rate = rates[0] }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.title3.weight(.semibold))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundStyle(selected ? Theme.onAccent : Color.primary)
            .background(selected ? Theme.accent : Theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var paceText: String {
        let weekly = (goal.rate * 7700).kcalText
        switch (goal.kind, goal.rate) {
        case (.lose, ...0.25): return String(localized: "Gentle and compatible with training: about −\(weekly) kcal over the week.")
        case (.lose, ...0.5): return String(localized: "About −\(weekly) kcal over the week. Watch your energy in key sessions.")
        case (.lose, _): return String(localized: "Fast: about −\(weekly) kcal over the week. Hard to sustain with a lot of training.")
        default: return String(localized: "About +\(weekly) kcal over the week, more on training days.")
        }
    }

    // MARK: Projection

    private var projection: some View {
        let current = engine.weight
        let target = goal.targetWeight
        return VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "flag.checkered").foregroundStyle(Theme.herb)
                VStack(alignment: .leading, spacing: 2) {
                    if let target {
                        Text(projectionTitle(current: current, target: target)).font(.subheadline.weight(.semibold))
                        Text("Then automatic maintenance").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No target weight").font(.subheadline.weight(.semibold))
                        Text("The goal keeps going until you change it").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Toggle("Target weight", isOn: Binding(
                    get: { goal.targetWeight != nil },
                    set: { goal.targetWeight = $0 ? ((current + (goal.kind == .lose ? -3 : 3)) * 2).rounded() / 2 : nil }
                ))
                .labelsHidden().tint(Theme.herb)
            }
            if let target {
                Stepper(value: Binding(get: { target }, set: { goal.targetWeight = $0 }), in: 40...150, step: 0.5) {
                    LabeledContent("Target weight", value: "\(target.formatted(.number.precision(.fractionLength(1)))) kg")
                }
                .font(.subheadline)
            }
        }
        .card(padding: DS.Spacing.s)
    }

    private func projectionTitle(current: Double, target: Double) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
        let weeks = abs(current - target) / max(goal.rate, 0.1)
        let date = Calendar.current.date(byAdding: .day, value: Int(weeks * 7), to: .now) ?? .now
        let reached = goal.kind == .lose ? current <= target : current >= target
        if reached { return String(localized: "Target reached: \(target.formatted(format)) kg") }
        return String(localized: "\(current.formatted(format)) → \(target.formatted(format)) kg around \(date.formatted(.dateTime.day().month()))")
    }

    // MARK: Coach

    private var coachSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Text("With your training plan").font(.headline)
                CoachBadge()
            }
            VStack(spacing: 0) {
                toggle("Adapt each day to the planned session", Text("More calories and carbs on training days"), $goal.adaptToPlan)
                Divider()
                toggle("No deficit on key session days", Text("Intervals, tests, important long sessions"), $goal.noDeficitOnKeyDays)
                    .disabled(!goal.adaptToPlan || goal.kind != .lose)
                Divider()
                toggle("Maintenance in race week", Text(raceText), $goal.maintainRaceWeek)
                    .disabled(goal.kind != .lose)
            }
            .card(padding: DS.Spacing.s)
            Text(coachStatus).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var raceText: String {
        guard let coach = engine.coach, let race = coach.raceDate else { return String(localized: "Uses the race date set in Coach") }
        return "\(coach.goal?.title ?? "") · \(race.formatted(.dateTime.day().month()))"
    }

    private var coachStatus: String {
        guard let coach = engine.coach else {
            return String(localized: "Coach plan not found. Open the Coach app once: it shares its plan with Popote on this iPhone.")
        }
        let upcoming = coach.sessions.filter { $0.date >= DayKey.string(.now) && $0.sport != "repos" }.count
        return String(localized: "Coach plan updated \(coach.updatedAt.formatted(.relative(presentation: .named))) · \(upcoming) upcoming sessions.")
    }

    private func toggle(_ title: LocalizedStringKey, _ detail: Text, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                detail.font(.caption).foregroundStyle(.secondary)
            }
        }
        .tint(Theme.herb)
        .padding(.vertical, 6)
    }

    // MARK: Protein

    private var proteinSection: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Protein").font(.headline)
            Stepper(value: $goal.proteinPerKg, in: 1.2...2.6, step: 0.1) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(goal.proteinPerKg.formatted(.number.precision(.fractionLength(1)))) g per kg").font(.subheadline.weight(.semibold))
                    Text("\(Int(engine.weight * goal.proteinPerKg)) g a day at \(engine.weight.formatted(.number.precision(.fractionLength(1)))) kg · aim higher in a deficit to keep muscle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .card(padding: DS.Spacing.s)
        }
    }
}

/// Small Coach badge (where the plan comes from).
struct CoachBadge: View {
    static let orange = Color(red: 1.0, green: 0.36, blue: 0.16)

    var body: some View {
        Label("Coach", systemImage: "figure.run.circle.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Self.orange)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Self.orange.opacity(0.12), in: Capsule())
    }
}

/// What the weekly check learned: the correction, with the weight trend vs. the planned one.
struct LearnedMaintenanceCard: View {
    let weights: [(date: Date, kg: Double)]
    let learned: LearnedMaintenance?
    let goal: GoalSettings

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("What Popote learned").font(.headline)
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                if let learned {
                    HStack(alignment: .firstTextBaseline) {
                        Text(learned.correction.signedKcal).font(.system(.title, design: .rounded, weight: .bold))
                        Text("kcal/day correction").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Label("\(learned.days) days", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(Theme.herb)
                    }
                } else {
                    Text("Learning…").font(.headline)
                }
                if weights.count >= 2 { chart }
                Text(explanation).font(.caption).foregroundStyle(.secondary)
            }
            .card(padding: DS.Spacing.s)
        }
    }

    private var explanation: String {
        guard let learned else {
            return String(localized: "After two weeks of logged meals and a few weigh-ins in Health, Popote compares your weight trend with what you ate and adjusts your targets. Checked every week.")
        }
        let measured = learned.measuredRate.formatted(.number.precision(.fractionLength(2)))
        let planned = goal.weeklyChange.formatted(.number.precision(.fractionLength(2)))
        return String(localized: "Your weight changes by \(measured) kg/week (goal: \(planned)). Popote adds this correction to every day's target and checks again every week.")
    }

    private var chart: some View {
        GeometryReader { geo in
            let kgs = weights.map(\.kg)
            let lo = (kgs.min() ?? 0) - 0.3, hi = (kgs.max() ?? 1) + 0.3
            let start = weights.first!.date, span = max(weights.last!.date.timeIntervalSince(start), 1)
            let x = { (date: Date) in geo.size.width * date.timeIntervalSince(start) / span }
            let y = { (kg: Double) in geo.size.height * (1 - (kg - lo) / (hi - lo)) }
            let trend = Self.trend(weights)
            ZStack {
                // Planned: from the first trend value at the goal's pace.
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y(trend.start)))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y(trend.start + goal.weeklyChange * span / 604_800)))
                }
                .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                ForEach(weights.indices, id: \.self) { i in
                    Circle().fill(Theme.accent.opacity(0.35)).frame(width: 5, height: 5)
                        .position(x: x(weights[i].date), y: y(weights[i].kg))
                }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y(trend.start)))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y(trend.end)))
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
        }
        .frame(height: 70)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Label("trend", systemImage: "line.diagonal").foregroundStyle(Theme.accent)
                Label("planned", systemImage: "line.diagonal").foregroundStyle(.secondary)
            }
            .font(.system(size: 9, weight: .medium))
        }
        .accessibilityHidden(true)
    }

    /// Least-squares line through the weigh-ins: value at the first and last date.
    static func trend(_ weights: [(date: Date, kg: Double)]) -> (start: Double, end: Double) {
        guard let first = weights.first?.date, let last = weights.last?.date, weights.count >= 2 else { return (0, 0) }
        let xs = weights.map { $0.date.timeIntervalSince(first) }
        let ys = weights.map(\.kg)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / max(xs.reduce(0) { $0 + pow($1 - mx, 2) }, 1)
        return (my - slope * mx, my + slope * (last.timeIntervalSince(first) - mx))
    }
}
