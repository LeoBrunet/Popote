import SwiftUI

/// Why today's target is what it is: the calculation, the macros of the day and the week.
struct DayTargetView: View {
    let day: Date

    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @AppStorage("goal") private var goal = GoalSettings()

    var body: some View {
        let engine = TargetEngine(health: health, goal: goal)
        let plan = engine.plan(for: day)
        let week = engine.week(of: day)

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                hero(plan)
                section("The calculation") { breakdown(plan).card(padding: DS.Spacing.s) }
                section("Today's macros") { macros(plan).card(padding: DS.Spacing.s) }
                section("The week") {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        WeekStrip(week: week, selected: day)
                        Text(weekSummary(week)).font(.caption).foregroundStyle(.secondary)
                        if engine.coach == nil {
                            Label("Install Coach and open it once to plan each day from your sessions.", systemImage: "figure.run.circle")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .card(padding: DS.Spacing.s)
                }
                NavigationLink { GoalView() } label: {
                    HStack {
                        Label(goalText, systemImage: "target")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .card(padding: DS.Spacing.s)
                }
            }
            .padding(DS.Spacing.m)
        }
        .background(Theme.background)
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).day().month()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private var goalText: String {
        switch goal.kind {
        case .lose: String(localized: "My goal: lose \(goal.rate.formatted()) kg/week")
        case .maintain: String(localized: "My goal: maintain")
        case .gain: String(localized: "My goal: gain \(goal.rate.formatted()) kg/week")
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(title).font(.headline)
            content()
        }
    }

    private func hero(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: 6) {
                Text(plan.kind.label)
                    .textCase(.uppercase)
                    .font(.caption2.weight(.bold)).foregroundStyle(plan.kind == .rest ? Color.secondary : plan.kind.color)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((plan.kind == .rest ? Color.gray : plan.kind.color).opacity(0.13), in: Capsule())
                if plan.trainings.contains(where: \.real) {
                    Label("Session done", systemImage: "applewatch").font(.caption2.weight(.bold)).foregroundStyle(Theme.herb)
                }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(plan.kcal.kcalText).font(.system(size: 44, weight: .bold, design: .rounded))
                Text("kcal").font(.callout).foregroundStyle(.secondary)
            }
            Text(explanation(plan)).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func explanation(_ plan: DayPlan) -> String {
        if let real = plan.trainings.first(where: \.real) {
            return String(localized: "\(real.title) burned \(real.kcal.kcalText) kcal according to Apple Health: the target uses the real number.")
        }
        switch plan.kind {
        case .rest:
            return plan.adjust < 0 ? String(localized: "No session planned: fewer carbs, and most of the week's deficit lands on days like this one.")
                                   : String(localized: "No session planned: fewer carbs today.")
        case .easy: return String(localized: "Easy session planned: a bit more to eat and moderate carbs.")
        case .key: return String(localized: "Key session planned: eat enough to perform, carbs up.")
        case .long:
            return plan.adjust < 0 ? String(localized: "Long session planned: eat more, especially carbs, with only a small deficit.")
                                   : String(localized: "Long session planned: eat more, especially carbs.")
        }
    }

    private func breakdown(_ plan: DayPlan) -> some View {
        VStack(spacing: 9) {
            if plan.fromHealth {
                row("bed.double.fill", String(localized: "Resting energy"), String(localized: "7-day average · Health"), plan.resting.kcalText)
                row("figure.walk", String(localized: "Everyday movement"), String(localized: "outside workouts · Health"), plan.movement.signedKcal)
            } else {
                row("slider.horizontal.3", String(localized: "Base target"), String(localized: "Settings (no Health data)"), plan.resting.kcalText)
            }
            ForEach(plan.trainings) { item in
                row(item.icon, item.title, item.real ? String(localized: "real · Apple Health") : String(localized: "planned in Coach · estimated"),
                    item.kcal.signedKcal, tint: plan.kind.color)
            }
            if plan.correction != 0 {
                row("chart.line.uptrend.xyaxis", String(localized: "Learned correction"), String(localized: "from your weight trend"), plan.correction.signedKcal, tint: Theme.herb)
            }
            if goal.kind != .maintain {
                HStack(spacing: DS.Spacing.s) {
                    Image(systemName: "target").font(.subheadline).foregroundStyle(Theme.accent).frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(goal.title).font(.subheadline)
                        Text(plan.adjustReason.text).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(plan.adjust == 0 ? "0" : plan.adjust.signedKcal).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("Daily target").font(.subheadline.weight(.bold))
                Spacer()
                Text("\(plan.kcal.kcalText) kcal").font(.subheadline.weight(.bold).monospacedDigit())
            }
        }
    }

    private func row(_ icon: String, _ title: String, _ detail: String, _ value: String, tint: Color = .secondary) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Image(systemName: icon).font(.subheadline).foregroundStyle(tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func macros(_ plan: DayPlan) -> some View {
        let perKg = { (value: Double) in value.formatted(.number.precision(.fractionLength(1))) }
        return VStack(spacing: DS.Spacing.s) {
            macro("Protein", plan.protein, String(localized: "\(perKg(plan.proteinPerKg)) g/kg · the same every day"), Theme.protein)
            macro("Carbs", plan.carbs, String(localized: "\(perKg(plan.carbsPerKg)) g/kg · follows the training"), Theme.carbs)
            macro("Fat", plan.fat, String(localized: "the rest · never below 0.8 g/kg"), Theme.fat)
        }
    }

    private func macro(_ name: LocalizedStringKey, _ grams: Double, _ why: String, _ color: Color) -> some View {
        HStack(spacing: DS.Spacing.s) {
            Circle().fill(color).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline)
                Text(why).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(grams)) g").font(.headline.monospacedDigit())
        }
    }

    private func weekSummary(_ week: [DayPlan]) -> String {
        let average = week.reduce(0) { $0 + $1.kcal } / 7
        let adjust = week.reduce(0) { $0 + $1.adjust }
        if goal.kind == .maintain || adjust == 0 { return String(localized: "Average \(average.kcalText) kcal/day.") }
        let kg = (adjust / 7700).formatted(.number.precision(.fractionLength(2)))
        return String(localized: "Average \(average.kcalText) kcal/day · \(adjust.signedKcal) kcal over the week ≈ \(kg) kg.")
    }
}
