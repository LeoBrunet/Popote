import SwiftData
import SwiftUI

struct RecipeDetailView: View {
    @Bindable var recipe: Recipe
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Query private var pantry: [PantryItem]
    @State private var servings = 2
    @State private var playing = false
    @State private var video = VideoController()
    @State private var editing = false
    @State private var matching: IngredientLine?
    @State private var logging = false
    @State private var confirmDelete = false

    var body: some View {
        let nutrition = NutritionEngine.evaluate(recipe)
        let factor = Double(servings) / Double(max(recipe.servings, 1))
        let pantryKeys = Set(pantry.map(\.key))

        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.l) {
                header
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    titleBlock
                    if recipe.needsReview { reviewBanner }
                    nutritionCard(nutrition)
                    ingredients(nutrition, factor: factor, pantryKeys: pantryKeys)
                    if !recipe.steps.isEmpty { steps }
                    actions(nutrition)
                }
                .padding(.horizontal, DS.Spacing.m)
            }
            .padding(.bottom, DS.Spacing.xl)
        }
        // Pushed views don't get the root's tab bar inset: keep the last buttons above it.
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 64) }
        .background(Theme.background)
        .ignoresSafeArea(edges: playing ? [] : .top)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    if let url = URL(string: recipe.sourceURL), !recipe.sourceURL.isEmpty {
                        Button { openURL(url) } label: { Label("Open the original", systemImage: "safari") }
                        ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 32, height: 32).background(.ultraThinMaterial, in: Circle())
                }
            }
        }
        .sheet(isPresented: $editing) { RecipeEditView(recipe: recipe) }
        .sheet(item: $matching) { line in IngredientMatchView(lines: Bindable(recipe).ingredients, line: line) }
        .sheet(isPresented: $logging) { LogRecipeSheet(recipe: recipe, perServing: nutrition.perServing) }
        .confirmationDialog("Delete this recipe?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(recipe)
                dismiss()
            }
        }
        .onAppear { servings = recipe.servings }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            if playing, let id = recipe.videoID, recipe.source.hasVideo {
                VideoEmbed(source: recipe.source, videoID: id, controller: video)
            } else {
                RecipePhoto(recipe: recipe, symbolSize: 64)
                    .overlay { LinearGradient(colors: [.black.opacity(0.25), .clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom) }
                    .overlay {
                        if recipe.videoID != nil && recipe.source.hasVideo {
                            Button { playing = true } label: {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 64, height: 64)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .accessibilityLabel("Play the video")
                        }
                    }
                HStack {
                    SourceBadge(source: recipe.source)
                    if !recipe.author.isEmpty {
                        Text(recipe.author).font(.caption.weight(.semibold)).foregroundStyle(.white)
                    }
                }
                .padding(DS.Spacing.s)
            }
        }
        .frame(height: headerHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .animation(.default, value: playing)
    }

    private var headerHeight: CGFloat {
        switch (recipe.source, playing) {
        case (.youtube, true): 226                       // 16:9 player below the navigation bar
        case (.tiktok, true), (.instagram, true): 560
        case (.tiktok, false), (.instagram, false): 340
        default: 280
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text(recipe.title).font(Theme.titleFont)
            HStack(spacing: DS.Spacing.m) {
                if let minutes = recipe.minutes { Label("\(minutes) min", systemImage: "clock") }
                Label("^[\(recipe.ingredients.count) ingredient](inflect: true)", systemImage: "basket")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var reviewBanner: some View {
        Button { editing = true } label: {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "sparkles").foregroundStyle(Theme.carbs)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check the import").font(.subheadline.weight(.semibold))
                    Text(recipe.ingredients.isEmpty
                         ? "No ingredients found. Add them from the caption."
                         : "Ingredients were read from the caption. Quantities may need a fix.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: DS.Spacing.s)
        }
        .buttonStyle(.plain)
    }

    private func nutritionCard(_ nutrition: NutritionEngine.RecipeNutrition) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            MacroSummary(nutrition: nutrition.perServing)
            if nutrition.missing > 0 {
                Label("^[\(nutrition.missing) ingredient](inflect: true) not counted yet. Tap to complete.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Theme.accent)
            } else if !recipe.ingredients.isEmpty {
                Label("\(nutrition.verified) of \(recipe.ingredients.count) ingredients checked", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    // MARK: Ingredients

    private func ingredients(_ nutrition: NutritionEngine.RecipeNutrition, factor: Double, pantryKeys: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack {
                Text("Ingredients").font(Theme.titleFont)
                Spacer()
                Stepper(value: $servings, in: 1...24) {
                    Text("^[\(servings) serving](inflect: true)").font(.subheadline.weight(.semibold))
                }
                .fixedSize()
            }
            VStack(spacing: 0) {
                ForEach(nutrition.lines, id: \.line.id) { item in
                    Button { matching = item.line } label: {
                        ingredientRow(item, factor: factor, inPantry: pantryKeys.contains(item.food?.id ?? TextKey.key(item.line.name)))
                    }
                    .buttonStyle(.plain)
                    if item.line.id != nutrition.lines.last?.line.id { Divider() }
                }
            }
            .card(padding: DS.Spacing.s)
        }
    }

    private func ingredientRow(_ item: IngredientNutrition, factor: Double, inPantry: Bool) -> some View {
        HStack(alignment: .center, spacing: DS.Spacing.s) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.line.name).font(.subheadline.weight(.medium))
                    if inPantry {
                        Image(systemName: "cabinet.fill").font(.caption2).foregroundStyle(Theme.herb)
                            .accessibilityLabel("In the pantry")
                    }
                }
                MatchBadge(kind: item.kind)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Units.format(item.line.quantity.map { $0 * factor }, unit: item.line.unit))
                    .font(.subheadline.monospacedDigit())
                if item.nutrition.kcal > 0 {
                    Text("\(Int((item.nutrition.kcal * factor).rounded())) kcal").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: Steps

    private var steps: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            Text("Steps").font(Theme.titleFont)
            ForEach(Array(recipe.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: DS.Spacing.s) {
                    Text("\(index + 1)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 26, height: 26)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(step.text).font(.body)
                        if let t = step.timestamp, recipe.source == .youtube {
                            Button {
                                playing = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { video.seek(to: t) }
                            } label: {
                                Label(String(format: "%d:%02d", t / 60, t % 60), systemImage: "play.circle.fill")
                                    .font(.caption.weight(.semibold).monospacedDigit())
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func actions(_ nutrition: NutritionEngine.RecipeNutrition) -> some View {
        VStack(spacing: DS.Spacing.s) {
            Button {
                recipe.inShoppingList.toggle()
                recipe.shoppingServings = servings
            } label: {
                Label(recipe.inShoppingList ? "In the shopping list" : "Add to groceries",
                      systemImage: recipe.inShoppingList ? "checkmark.circle.fill" : "cart.badge.plus")
            }
            .buttonStyle(PrimaryButtonStyle(secondary: recipe.inShoppingList))
            Button { logging = true } label: {
                Label("I'm eating it", systemImage: "fork.knife")
            }
            .buttonStyle(PrimaryButtonStyle(secondary: true))
            .disabled(nutrition.perServing.kcal == 0)
        }
    }
}

/// Log servings of a recipe in the journal.
struct LogRecipeSheet: View {
    let recipe: Recipe
    let perServing: Nutrition
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var portions = 1.0
    @State private var meal = Meal.now
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $portions, in: 0.5...6, step: 0.5) {
                        Text(Units.servings(portions))
                    }
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.name).tag($0) }
                    }
                    DatePicker("When", selection: $date)
                }
                Section {
                    MacroSummary(nutrition: perServing * portions, caption: "kcal")
                }
            }
            .navigationTitle(recipe.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        let entry = JournalEntry(date: date, meal: meal, title: recipe.title,
                                                 detail: Units.servings(portions),
                                                 nutrition: perServing * portions)
                        entry.recipeID = recipe.id
                        entry.setAmount(portions, unit: "serving")
                        entry.lines = recipe.ingredients.map { $0.scaled(by: portions / Double(max(recipe.servings, 1))) }
                        context.insert(entry)
                        Task {
                            entry.healthUUID = await health.save(entry)
                            dismiss()
                        }
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
