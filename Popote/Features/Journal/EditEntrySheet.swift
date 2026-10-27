import SwiftData
import SwiftUI

/// Edit a logged meal. Saving rewrites it in Apple Health (old sample deleted, new one saved).
/// Meals logged from a recipe (or by Claude) keep their ingredients: swapping one recomputes the meal
/// and can be saved back to the recipe.
struct EditEntrySheet: View {
    let entry: JournalEntry
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var meal = Meal.lunch
    @State private var date = Date()
    @State private var amount = 1.0
    @State private var grams = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var shown = Nutrition.zero      // values behind the text fields, kept exact
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var lines: [IngredientLine] = []
    @State private var loadedLines: [IngredientLine] = []
    @State private var matching: IngredientLine?
    @State private var newLine = ""
    @State private var recipe: Recipe?
    @State private var updateRecipe = false

    private var isGrams: Bool { entry.amountUnit == "g" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.name).tag($0) }
                    }
                    DatePicker("When", selection: $date)
                }

                if entry.amount != nil {
                    Section {
                        if isGrams {
                            HStack {
                                Text("Quantity")
                                Spacer()
                                TextField("100", text: $grams)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                    .onChange(of: grams) { _, value in
                                        if let g = number(value), g > 0 { rescale(to: g) }
                                    }
                                Text("g").foregroundStyle(.secondary)
                            }
                        } else {
                            Stepper(value: $amount, in: 0.5...12, step: 0.5) { Text(Units.servings(amount)) }
                                .onChange(of: amount) { _, value in rescale(to: value) }
                        }
                    } footer: {
                        Text("Changing the quantity updates the calories and macros.")
                    }
                }

                if !lines.isEmpty { ingredientsSection }

                Section("Nutrition") {
                    field("Calories", $kcal, unit: "kcal")
                    field("Protein", $protein, unit: "g")
                    field("Carbs", $carbs, unit: "g")
                    field("Fat", $fat, unit: "g")
                }

                Section {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } footer: {
                    if health.connected {
                        Label("Changes are saved to Apple Health too.", systemImage: "heart.fill")
                    }
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save", action: save).bold() }
                }
            }
            .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let uuid = entry.healthUUID { Task { await health.delete(healthUUID: uuid) } }
                    context.delete(entry)
                    dismiss()
                }
            }
            .onAppear(perform: load)
            .sheet(item: $matching) { line in IngredientMatchView(lines: $lines, line: line, substitute: true) }
            .onChange(of: lines) { recompute() }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach(lines) { line in
                let item = NutritionEngine.evaluate(line)
                Button { matching = line } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(line.name).foregroundStyle(Color.primary)
                            if !loadedLines.contains(line) {
                                Text("Changed").font(.caption2.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(Units.format(line.quantity, unit: line.unit)).font(.subheadline.monospacedDigit()).foregroundStyle(Color.primary)
                            Text("\(Int(item.nutrition.kcal.rounded())) kcal").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { lines.remove(atOffsets: $0) }
            HStack {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                TextField("Add an ingredient (\"20 g butter\")", text: $newLine)
                    .submitLabel(.done)
                    .onSubmit {
                        let text = newLine.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { lines.append(IngredientParser.parse(text)) }
                        newLine = ""
                    }
            }
            if let recipe, differsFromRecipe, !isGrams {
                Toggle(isOn: $updateRecipe) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also update the recipe")
                        Text("Saves these ingredients in \(recipe.title), for \(Units.servings(Double(recipe.servings)))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(Theme.herb)
            }
        } header: {
            Text("Ingredients")
        } footer: {
            Text("Tap an ingredient to swap it for another (same weight) or change its weight. Swipe to remove it.")
        }
    }

    private func field(_ label: LocalizedStringKey, _ value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func load() {
        title = entry.title
        meal = entry.meal
        date = entry.date
        amount = entry.amount ?? 1
        grams = entry.amount.map { "\(Int($0.rounded()))" } ?? ""
        show(entry.nutrition)
        lines = entry.lines
        loadedLines = lines
        if let id = entry.recipeID {
            recipe = try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.id == id })).first
        }
    }

    /// The meal's ingredients aren't the recipe's (swapped, added, removed or re-weighed), for the same servings.
    private var differsFromRecipe: Bool {
        guard let recipe, let original = entry.amount, original > 0 else { return false }
        let expected = recipe.ingredients.map { $0.scaled(by: original / Double(max(recipe.servings, 1))) }
        guard expected.count == lines.count else { return true }
        return zip(expected, lines).contains { a, b in
            let ga = NutritionEngine.evaluate(a).grams ?? 0, gb = NutritionEngine.evaluate(b).grams ?? 0
            return a.name != b.name || a.ignored != b.ignored || abs(ga - gb) > max(1, ga * 0.02)
        }
    }

    private var linesTotal: Nutrition { lines.reduce(.zero) { $0 + NutritionEngine.evaluate($1).nutrition } }

    /// Amount now shown vs. the amount the ingredients were stored for.
    private var amountFactor: Double {
        guard let original = entry.amount, original > 0 else { return 1 }
        let current = isGrams ? (number(grams) ?? original) : amount
        return current > 0 ? current / original : 1
    }

    /// The ingredients changed: the meal's nutrition is theirs.
    private func recompute() {
        guard !lines.isEmpty, lines != loadedLines else { return }
        show(linesTotal * amountFactor)
    }

    private func show(_ n: Nutrition) {
        shown = n
        kcal = "\(Int(n.kcal.rounded()))"
        protein = n.protein.formatted(.number.precision(.fractionLength(0...1)))
        carbs = n.carbs.formatted(.number.precision(.fractionLength(0...1)))
        fat = n.fat.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Scale the logged nutrition from the original amount to the new one.
    private func rescale(to value: Double) {
        guard let original = entry.amount, original > 0 else { return }
        let base = lines != loadedLines ? linesTotal : entry.nutrition
        show(base * (value / original))
    }

    private func number(_ text: String) -> Double? {
        let parsed = (try? Double(text, format: .number)) ?? Double(text.replacingOccurrences(of: ",", with: "."))
        return parsed
    }

    private func save() {
        let factor = amountFactor
        if !lines.isEmpty || !loadedLines.isEmpty {
            let eaten = lines.map { $0.scaled(by: factor) }
            entry.lines = eaten
            if updateRecipe, let recipe, differsFromRecipe, !isGrams, amount > 0 {
                recipe.ingredients = eaten.map { $0.scaled(by: Double(recipe.servings) / amount) }
            }
        }
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry.title : title
        entry.meal = meal
        entry.date = date
        if entry.amount != nil {
            if isGrams, let g = number(grams), g > 0 { entry.setAmount(g, unit: "g") }
            if !isGrams { entry.setAmount(amount, unit: "serving") }
        }
        // Fields left as displayed keep their exact value (no rounding drift); typed ones win.
        let untouched = Nutrition(kcal: shown.kcal, protein: shown.protein, carbs: shown.carbs, fat: shown.fat)
        entry.kcal = kcal == "\(Int(untouched.kcal.rounded()))" ? untouched.kcal : number(kcal) ?? untouched.kcal
        entry.protein = protein == untouched.protein.formatted(.number.precision(.fractionLength(0...1))) ? untouched.protein : number(protein) ?? untouched.protein
        entry.carbs = carbs == untouched.carbs.formatted(.number.precision(.fractionLength(0...1))) ? untouched.carbs : number(carbs) ?? untouched.carbs
        entry.fat = fat == untouched.fat.formatted(.number.precision(.fractionLength(0...1))) ? untouched.fat : number(fat) ?? untouched.fat

        saving = true
        Task {
            // Health samples can't be edited: replace the old one.
            if let old = entry.healthUUID { await health.delete(healthUUID: old) }
            entry.healthUUID = await health.save(entry)
            saving = false
            dismiss()
        }
    }
}
