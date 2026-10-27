import SwiftData
import SwiftUI

/// A meal sent to Claude: wait for the ingredients (Claude works in the Claude app), edit them,
/// then log the meal and/or keep it as a recipe.
struct DescribeMealView: View {
    @Bindable var draft: MealDraft
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(ClaudeSync.self) private var sync
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var editing: IngredientLine?
    @State private var newLine = ""
    @State private var savedRecipe = false
    @State private var checking = false

    private var nutrition: [IngredientNutrition] { draft.lines.map(NutritionEngine.evaluate) }
    private var total: Nutrition { nutrition.reduce(.zero) { $0 + $1.nutrition } }

    var body: some View {
        Group {
            if draft.analyzed { result } else { waiting }
        }
        .background(Theme.background)
        .navigationTitle(draft.meal.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { line in LineEditor(line: line) { updated in replace(updated) } }
        // Claude answers in its own app: check when we come back, and every few seconds while waiting here.
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await check() } } }
        .task(id: draft.analyzed) {
            while !draft.analyzed && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                await check()
            }
        }
    }

    // MARK: Waiting

    private var waiting: some View {
        VStack(spacing: DS.Spacing.l) {
            Spacer()
            if let photo = draft.photo, let image = UIImage(data: photo) {
                Image(uiImage: image).resizable().scaledToFill().frame(width: 160, height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            ClaudeMark(size: 54)
            Text("Claude is looking at your meal").font(Theme.titleFont).multilineTextAlignment(.center)
            if !draft.text.isEmpty {
                Text("« \(draft.text) »").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text("Send the message in the Claude app, then come back here: the ingredients will show up to review.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            VStack(spacing: DS.Spacing.s) {
                Button { ClaudeLink.open(ClaudeLink.analyzeMeal(draft.requestId)) } label: {
                    Label("Open Claude", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button { Task { await check() } } label: {
                    HStack { Text("Check now"); if checking { ProgressView() } }
                }
                .buttonStyle(PrimaryButtonStyle(secondary: true))
                Button(role: .destructive) { stopWaiting() } label: {
                    Label("Stop waiting", systemImage: "xmark")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.top, DS.Spacing.xs)
            }
            if let error = sync.lastError { Text(error).font(.caption).foregroundStyle(Theme.accent) }
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
    }

    private func check() async {
        guard !draft.analyzed, !checking else { return }
        checking = true
        try? await sync.pull(context: context)
        checking = false
    }

    /// Leaves this screen first, then deletes the draft (the view must not outlive its model).
    private func stopWaiting() {
        let draft = draft
        onDone()
        dismiss()
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            await sync.cancelMeal(draft, context: context)
        }
    }

    // MARK: Result

    private var result: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DS.Spacing.s) {
                    if let photo = draft.photo, let image = UIImage(data: photo) {
                        Image(uiImage: image).resizable().scaledToFill().frame(height: 150).frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    } else if !draft.text.isEmpty {
                        Label("« \(draft.text) »", systemImage: "text.bubble.fill")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    TextField("Name", text: $draft.title).font(Theme.titleFont)
                    MacroSummary(nutrition: total, caption: "kcal (estimated)")
                }
                .padding(.vertical, 4)
            }

            Section {
                ForEach(nutrition, id: \.line.id) { item in
                    Button { editing = item.line } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.line.name).foregroundStyle(Color.primary)
                                MatchBadge(kind: item.kind)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(quantity(item.line)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.primary)
                                Text("\(Int(item.nutrition.kcal.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in var lines = draft.lines; lines.remove(atOffsets: offsets); draft.lines = lines }
                HStack {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                    TextField("Add an ingredient (\"1 apple\", \"20 g butter\")", text: $newLine)
                        .submitLabel(.done)
                        .onSubmit(addLine)
                }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    Text("Tap to edit").textCase(nil)
                }
            }

            Section {
                Button { logMeal() } label: { Label("Add to \(draft.meal.lowercasedName)", systemImage: "checkmark") }
                    .buttonStyle(PrimaryButtonStyle())
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                Button { saveRecipe() } label: {
                    Label(savedRecipe ? "Saved as a recipe" : "Save as a recipe", systemImage: savedRecipe ? "checkmark.circle.fill" : "book.closed")
                }
                .buttonStyle(PrimaryButtonStyle(secondary: true))
                .disabled(savedRecipe)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            .disabled(draft.lines.isEmpty)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Actions

    private func quantity(_ line: IngredientLine) -> String {
        let written = Units.format(line.quantity, unit: line.unit)
        if let grams = line.gramsOverride, line.unit != "g" {
            return written.isEmpty ? "\(Int(grams.rounded())) g" : "\(written) · \(Int(grams.rounded())) g"
        }
        return written
    }

    private func replace(_ line: IngredientLine) {
        var lines = draft.lines
        if let i = lines.firstIndex(where: { $0.id == line.id }) { lines[i] = line }
        draft.lines = lines
    }

    private func addLine() {
        let text = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft.lines = draft.lines + [IngredientParser.parse(text)]
        newLine = ""
    }

    private func logMeal() {
        let day = draft.day
        let date = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let name = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? String(localized: "Meal") : draft.title
        let entry = JournalEntry(date: date, meal: draft.meal, title: name, detail: "", nutrition: total)
        entry.setAmount(1, unit: "serving")
        context.insert(entry)
        context.delete(draft)
        Task {
            entry.healthUUID = await health.save(entry)
            onDone()
            dismiss()
        }
    }

    private func saveRecipe() {
        let recipe = Recipe(title: draft.title.isEmpty ? String(localized: "New recipe") : draft.title, source: .claude)
        recipe.servings = 1
        recipe.shoppingServings = 1
        recipe.ingredients = draft.lines.map { var line = $0; line.guessed = false; return line }
        recipe.imageData = draft.photo
        recipe.rawText = draft.text.isEmpty ? nil : draft.text
        context.insert(recipe)
        savedRecipe = true
    }
}

/// Edit one ingredient: name, quantity as written, and weight.
private struct LineEditor: View {
    let line: IngredientLine
    let save: (IngredientLine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var grams = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("g", text: $grams).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text("g").foregroundStyle(.secondary)
                }
            }
            .navigationTitle(line.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = line
                        let nameChanged = name != line.name
                        updated.name = name
                        if nameChanged { updated.foodID = nil }
                        if let g = Double(grams.replacingOccurrences(of: ",", with: ".")), g > 0 {
                            // Keep Claude's estimate in step with the new weight.
                            if let old = line.gramsOverride, old > 0, let e = line.estimate {
                                let k = g / old
                                updated.estimate = EstimatedNutrition(kcal: e.kcal * k, protein: e.protein * k, carbs: e.carbs * k, fat: e.fat * k)
                            }
                            updated.gramsOverride = g
                            updated.quantity = g
                            updated.unit = "g"
                        }
                        save(updated)
                        dismiss()
                    }
                }
            }
            .onAppear {
                name = line.name
                grams = line.gramsOverride.map { "\(Int($0.rounded()))" } ?? ""
            }
        }
        .presentationDetents([.medium])
    }
}

extension Meal {
    /// "lunch" / "déjeuner", for sentences.
    var lowercasedName: String {
        switch self {
        case .breakfast: String(localized: "breakfast")
        case .lunch: String(localized: "lunch")
        case .snack: String(localized: "snack")
        case .dinner: String(localized: "dinner")
        }
    }
}
