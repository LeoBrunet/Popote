import SwiftData
import SwiftUI

struct JournalView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Query(sort: \JournalEntry.date) private var allEntries: [JournalEntry]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var adding: Meal?
    @State private var editing: JournalEntry?
    @State private var reviewing: MealDraft?
    @State private var showTarget = false
    @AppStorage("coachTileHidden") private var coachTileHidden = false
    @AppStorage("goal") private var goal = GoalSettings()
    @Query(sort: \MealDraft.createdAt, order: .reverse) private var drafts: [MealDraft]

    private var entries: [JournalEntry] {
        allEntries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
    }

    var body: some View {
        let total = entries.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let targets = TargetEngine(health: health, goal: goal).plan(for: day)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    ScreenHeader(title: "Journal") { EmptyView() }
                    dayPicker
                    summary(total, targets)
                    healthCard(targets)
                    Button { showTarget = true } label: { DayTargetCard(plan: targets) }.buttonStyle(.plain)
                    if CoachPlan.load() == nil && !coachTileHidden {
                        CoachInstallTile { withAnimation { coachTileHidden = true } }
                    }
                    if !drafts.isEmpty { draftsSection }
                    ForEach(Meal.allCases) { meal in mealSection(meal) }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(Theme.background)
            .statusBarBackdrop()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $adding) { meal in LogMealSheet(meal: meal, day: day) }
            .sheet(item: $editing) { entry in EditEntrySheet(entry: entry) }
            .sheet(item: $reviewing) { draft in NavigationStack { DescribeMealView(draft: draft) } }
            .sheet(isPresented: $showTarget) { NavigationStack { DayTargetView(day: day) } }
        }
    }

    private var dayPicker: some View {
        let isToday = Calendar.current.isDateInToday(day)
        return HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(isToday ? String(localized: "Today · \(day.formatted(.dateTime.weekday(.wide).day().month()))")
                         : day.formatted(.dateTime.weekday(.wide).day().month()))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }.disabled(isToday).opacity(isToday ? 0.3 : 1)
        }
        .foregroundStyle(Theme.accent)
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day)!
    }

    private func summary(_ total: Nutrition, _ targets: DayPlan) -> some View {
        HStack(spacing: DS.Spacing.l) {
            ZStack {
                Ring(value: total.kcal, target: targets.kcal, color: Theme.accent, lineWidth: 12)
                VStack(spacing: 0) {
                    let remaining = targets.kcal - total.kcal
                    Text("\(Int(abs(remaining)))").font(.system(.title2, design: .rounded, weight: .bold))
                    Text(remaining >= 0 ? "left" : "over").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)
            VStack(spacing: DS.Spacing.s) {
                macroLine("Protein", total.protein, targets.protein, Theme.protein)
                macroLine("Carbs", total.carbs, targets.carbs, Theme.carbs)
                macroLine("Fat", total.fat, targets.fat, Theme.fat)
            }
        }
        .card()
        .contentShape(Rectangle())
        .onTapGesture { showTarget = true }
    }

    private func macroLine(_ label: LocalizedStringKey, _ value: Double, _ target: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) g").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                Capsule().fill(color.opacity(0.15))
                    .overlay(alignment: .leading) {
                        Capsule().fill(color).frame(width: geo.size.width * min(value / max(target, 1), 1))
                    }
            }
            .frame(height: 6)
        }
    }

    @ViewBuilder
    private func healthCard(_ targets: DayPlan) -> some View {
        if health.available {
            Button {
                if !health.connected { Task { await health.connect() } }
            } label: {
                HStack(spacing: DS.Spacing.s) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(Theme.health)
                        .frame(width: 36, height: 36)
                        .background(Theme.health.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        if health.connected {
                            Text("Apple Health up to date").font(.subheadline.weight(.semibold))
                            Text("\(Int(health.activeToday)) active kcal today · meals saved to Health")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Connect Apple Health").font(.subheadline.weight(.semibold))
                            Text("Save your meals and adjust the target to your activity")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if !health.connected { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                }
                .card(padding: DS.Spacing.s)
            }
            .buttonStyle(.plain)
        }
    }

    private func mealSection(_ meal: Meal) -> some View {
        let items = entries.filter { $0.meal == meal }
        return VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            HStack {
                Label(meal.name, systemImage: meal.icon).font(.headline)
                Spacer()
                Text("\(Int(items.reduce(0) { $0 + $1.kcal })) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(items) { entry in
                    Button { editing = entry } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.subheadline)
                            Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(entry.kcal))").font(.subheadline.monospacedDigit())
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) { delete(entry) } label: { Label("Delete", systemImage: "trash") }
                    }
                    Divider()
                }
                // One "Add" per meal; the sheet offers describe, photo, scan, recipe and recents.
                Button { adding = meal } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill").font(.title3)
                        Text("Add").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("Describe · Photo · Scan · Recipe").font(.caption2).foregroundStyle(.secondary)
                    }
                    .foregroundStyle(Theme.accent)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .card(padding: DS.Spacing.s)
        }
    }

    /// Meals sent to Claude: waiting for the ingredients, or ready to review.
    private var draftsSection: some View {
        VStack(spacing: DS.Spacing.xs) {
            ForEach(drafts) { draft in
                Button { reviewing = draft } label: {
                    HStack(spacing: DS.Spacing.s) {
                        ClaudeMark(size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(draft.analyzed ? "Your meal is ready to review" : "Waiting for Claude…").font(.subheadline.weight(.semibold))
                            Text(draft.analyzed ? draft.title : (draft.text.isEmpty ? String(localized: "Photo of your plate") : draft.text))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .card(padding: DS.Spacing.s)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button(role: .destructive) { context.delete(draft) } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
    }

    private func delete(_ entry: JournalEntry) {
        if let uuid = entry.healthUUID { Task { await health.delete(healthUUID: uuid) } }
        context.delete(entry)
        try? context.save()
    }
}
