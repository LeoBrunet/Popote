import SwiftData
import SwiftUI

/// Add to a meal: a recipe serving, a scanned product, or a generic food by weight.
struct AddFoodSheet: View {
    let meal: Meal
    let day: Date
    var initialMode = Mode.recipe
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var mode = Mode.recipe
    @State private var query = ""
    @State private var pending: Pending?
    @State private var scanError: String?

    enum Mode: Hashable { case recipe, scan, food }

    /// Something picked, waiting for its quantity.
    struct Pending: Identifiable {
        let id = UUID()
        let title: String
        let per100g: Nutrition?        // foods and products
        let perServing: Nutrition?     // recipes
        var servingGrams: Double?
        var recipeID: UUID?
        var product: ProductSnapshot?   // scanned product, can also go into a recipe
        var foodID: String?             // generic food, same

        /// Ingredient line for `grams` of this product or food (to add it to a recipe or keep it with the meal).
        func line(grams: Double) -> IngredientLine? {
            guard product != nil || foodID != nil else { return nil }
            let name = product?.name ?? title
            return IngredientLine(raw: "\(Units.formatNumber(grams)) g \(name)", name: name, quantity: grams, unit: "g",
                                  foodID: foodID, product: product, gramsOverride: grams)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $mode) {
                    Text("Recipe").tag(Mode.recipe)
                    Text("Scan").tag(Mode.scan)
                    Text("Food").tag(Mode.food)
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .recipe: recipeList
                case .scan: scanner
                case .food: foodList
                }
            }
            .background(Theme.background)
            .navigationTitle(meal.name)
            .onAppear { mode = initialMode }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $pending) { item in QuantitySheet(item: item) { save(item, nutrition: $0, amount: $1, unit: $2) } }
        }
    }

    private var recipeList: some View {
        List(recipes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { recipe in
            let perServing = NutritionEngine.evaluate(recipe).perServing
            Button {
                pending = Pending(title: recipe.title, per100g: nil, perServing: perServing, recipeID: recipe.id)
            } label: {
                HStack {
                    RecipePhoto(recipe: recipe, symbolSize: 14).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(recipe.title).foregroundStyle(Color.primary).lineLimit(2)
                    Spacer()
                    Text("\(Int(perServing.kcal)) kcal").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query)
        .overlay {
            if recipes.isEmpty { ContentUnavailableView("No recipes yet", systemImage: "book") }
        }
    }

    private var scanner: some View {
        VStack {
            BarcodeScanner { code in
                Task {
                    if let product = try? await OpenFoodFacts.product(barcode: code) {
                        pending = Pending(title: [product.brand, product.name].compactMap { $0 }.joined(separator: " · "),
                                          per100g: Nutrition(kcal: product.kcal, protein: product.protein, carbs: product.carbs, fat: product.fat),
                                          perServing: nil, servingGrams: product.servingGrams, product: product)
                    } else {
                        scanError = String(localized: "Product \(code) isn't in Open Food Facts.")
                    }
                }
            }
            if let scanError { Text(scanError).font(.footnote).foregroundStyle(Theme.accent).padding() }
        }
    }

    private var foodList: some View {
        List(FoodTable.search(query).filter { !$0.staple }) { food in
            Button {
                pending = Pending(title: food.name, per100g: food.per100g, perServing: nil, servingGrams: food.pieceGrams, foodID: food.id)
            } label: {
                HStack {
                    Text(food.name).foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(Int(food.per100g.kcal)) kcal/100 g").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .searchable(text: $query, prompt: "Search a food")
    }

    private func save(_ item: Pending, nutrition: Nutrition, amount: Double, unit: String) {
        let date = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let entry = JournalEntry(date: date, meal: meal, title: item.title, detail: "", nutrition: nutrition)
        entry.setAmount(amount, unit: unit)
        entry.recipeID = item.recipeID
        if let recipe = recipes.first(where: { $0.id == item.recipeID }) {
            entry.lines = recipe.ingredients.map { $0.scaled(by: amount / Double(max(recipe.servings, 1))) }
        } else if let line = item.line(grams: amount) {
            entry.lines = [line]
        }
        context.insert(entry)
        try? context.save()
        Task {
            entry.healthUUID = await health.save(entry)
            try? context.save()
            dismiss()
        }
    }
}

private struct QuantitySheet: View {
    let item: AddFoodSheet.Pending
    let save: (Nutrition, Double, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var servings = 1.0
    @State private var grams = ""
    @State private var pickingRecipe = false
    @State private var addedTo: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                if item.perServing != nil {
                    Stepper(value: $servings, in: 0.5...6, step: 0.5) { Text(Units.servings(servings)) }
                } else {
                    HStack {
                        Text("Quantity")
                        Spacer()
                        TextField("100", text: $grams).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("g").foregroundStyle(.secondary)
                    }
                    if let serving = item.servingGrams {
                        Button("1 serving (\(Int(serving)) g)") { grams = "\(Int(serving))" }
                    }
                }
                Section { MacroSummary(nutrition: nutrition, caption: "kcal") }
                if item.line(grams: 1) != nil {
                    Section {
                        if !addedTo.isEmpty {
                            Label(String(localized: "Added to \(addedTo.formatted(.list(type: .and)))"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.herb)
                        }
                        Button { pickingRecipe = true } label: {
                            Label(addedTo.isEmpty ? "Add to a recipe" : "Add to another recipe", systemImage: "book.closed")
                        }
                        .disabled(gramsValue <= 0)
                    } footer: {
                        Text("Adds \(Units.formatNumber(gramsValue)) g to a recipe's ingredients. You can still log it afterwards.")
                    }
                }
            }
            .sheet(isPresented: $pickingRecipe) {
                RecipePickerSheet { recipe in
                    if let line = item.line(grams: gramsValue) {
                        recipe.ingredients.append(line)
                        try? recipe.modelContext?.save()
                        addedTo.append(recipe.title)
                    }
                }
            }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        if item.perServing != nil { save(nutrition, servings, "serving") } else { save(nutrition, gramsValue, "g") }
                        dismiss()
                    }
                    .disabled(nutrition.kcal == 0 && item.perServing == nil && gramsValue == 0)
                }
            }
            .onAppear { if let serving = item.servingGrams { grams = "\(Int(serving))" } else { grams = "100" } }
        }
        .presentationDetents(item.line(grams: 1) != nil ? [.large] : [.medium])
    }

    private var gramsValue: Double { Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    private var nutrition: Nutrition {
        if let perServing = item.perServing { return perServing * servings }
        return (item.per100g ?? .zero) * (gramsValue / 100)
    }
}

/// Pick one of your recipes (to add an ingredient to it).
struct RecipePickerSheet: View {
    let pick: (Recipe) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Recipe.title) private var recipes: [Recipe]
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List(recipes.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }) { recipe in
                Button {
                    pick(recipe)
                    dismiss()
                } label: {
                    HStack {
                        RecipePhoto(recipe: recipe, symbolSize: 14).frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(recipe.title).foregroundStyle(Color.primary).lineLimit(2)
                            Text("^[\(recipe.ingredients.count) ingredient](inflect: true)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query)
            .overlay { if recipes.isEmpty { ContentUnavailableView("No recipes yet", systemImage: "book") } }
            .navigationTitle("Add to a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
