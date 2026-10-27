import Foundation
import Observation
import OSLog
import SwiftData

/// A meal sent to Claude: waits for the analysis, then is reviewed and logged (or saved as a recipe).
@Model
final class MealDraft {
    var id: UUID = UUID()
    var requestId: String = ""
    var mealRaw: String = Meal.lunch.rawValue
    var day: Date = Date()
    var text: String = ""
    @Attribute(.externalStorage) var photo: Data?
    var title: String = ""
    var linesData: Data = Data()
    var analyzed: Bool = false
    var createdAt: Date = Date()

    init(requestId: String, meal: Meal, day: Date, text: String, photo: Data?) {
        self.requestId = requestId
        self.mealRaw = meal.rawValue
        self.day = day
        self.text = text
        self.photo = photo
    }

    var meal: Meal { Meal(rawValue: mealRaw) ?? .lunch }

    var lines: [IngredientLine] {
        get { (try? JSONDecoder().decode([IngredientLine].self, from: linesData)) ?? [] }
        set { linesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

/// Keeps the Popote server in step with the app: registers once, shares the context Claude reads
/// (pantry, recipes, today's targets), and brings in what Claude saved (meal analyses, recipes).
@MainActor
@Observable
final class ClaudeSync {
    private let log = Logger(subsystem: "com.leobrunet.popote", category: "claude")
    var connectorURL: String?
    var claudeConnected = false
    var lastError: String?
    /// Recipes Claude just added, announced on the Recettes screen.
    var newRecipes: [(id: UUID, title: String)] = []

    var serverURL: URL {
        didSet { UserDefaults.standard.set(serverURL.absoluteString, forKey: "serverURL") }
    }

    init() {
        serverURL = UserDefaults.standard.string(forKey: "serverURL").flatMap(URL.init(string:)) ?? PopoteServer.defaultURL
    }

    private var token: String? {
        get { Keychain.get("popote.appToken") }
        set { if let newValue { Keychain.set(newValue, for: "popote.appToken") } else { Keychain.delete("popote.appToken") } }
    }

    private var api: PopoteServer { PopoteServer(baseURL: serverURL, token: token) }

    /// Registers this install on first use, then refreshes the connector URL and Claude's status.
    func bootstrap() async {
        do {
            if token == nil {
                let registration = try await api.register()
                token = registration.appToken
                connectorURL = registration.connectorUrl
            }
            let me: PopoteServer.Me
            do {
                me = try await api.me()
            } catch PopoteServer.ServerError.http(401, _) {
                let registration = try await api.register()
                token = registration.appToken
                me = try await api.me()
            }
            connectorURL = me.connectorUrl
            claudeConnected = me.claude.connectedAt != nil
            lastError = nil
        } catch {
            log.error("bootstrap: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func resetRegistration() async {
        token = nil
        connectorURL = nil
        claudeConnected = false
        await bootstrap()
    }

    /// Shares the context, then imports analyses and recipes. Called when the app comes to the foreground.
    func sync(context: ModelContext, health: HealthService) async {
        if token == nil { await bootstrap() }
        guard token != nil else { return }
        do {
            do {
                try await api.putContext(makeContext(context, health: health))
            } catch PopoteServer.ServerError.http(401, _) {
                // Unknown token (server reset or changed): register again, then retry once.
                await resetRegistration()
                try await api.putContext(makeContext(context, health: health))
            }
            try await pull(context: context)
            lastError = nil
        } catch {
            log.error("sync: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func pull(context: ModelContext) async throws {
        let inbox = try await api.inbox()
        var meals: [String] = []
        for analysis in inbox.mealAnalyses {
            let requestId = analysis.requestId
            let draft = try context.fetch(FetchDescriptor<MealDraft>(predicate: #Predicate { $0.requestId == requestId })).first
            if let draft {
                draft.title = analysis.title
                draft.lines = analysis.ingredients.map(Self.line)
                draft.analyzed = true
            }
            meals.append(requestId)
        }
        var recipes: [String] = []
        for item in inbox.recipes {
            let recipe = Recipe(title: item.title, source: .claude)
            recipe.author = "Claude"
            recipe.servings = item.servings
            recipe.shoppingServings = item.servings
            recipe.minutes = item.minutes
            recipe.rawText = item.summary
            recipe.ingredients = item.ingredients.map { IngredientParser.parse("\(Units.formatNumber($0.quantity)) \($0.unit) \($0.name)") }
            recipe.steps = item.steps.map { RecipeStep(text: $0) }
            context.insert(recipe)
            newRecipes.append((recipe.id, recipe.title))
            recipes.append(item.id)
        }
        try? context.save()
        if !meals.isEmpty || !recipes.isEmpty {
            try await api.acknowledge(mealRequests: meals, recipes: recipes)
        }
    }

    /// Sends a meal to the server and opens Claude on it. Returns the local draft that will receive the answer.
    func sendMeal(text: String, photo: Data?, meal: Meal, day: Date, context: ModelContext) async throws -> MealDraft {
        if token == nil { await bootstrap() }
        let id = try await api.createMealRequest(meal: meal.rawValue, description: text.isEmpty ? nil : text, photo: photo)
        let draft = MealDraft(requestId: id, meal: meal, day: day, text: text, photo: photo)
        context.insert(draft)
        try? context.save()
        ClaudeLink.open(ClaudeLink.analyzeMeal(id))
        return draft
    }

    /// Gives up on a meal: drops the draft and tells the server, so Claude no longer sees it as pending.
    func cancelMeal(_ draft: MealDraft, context: ModelContext) async {
        let requestId = draft.requestId
        context.delete(draft)
        try? context.save()
        try? await api.acknowledge(mealRequests: [requestId], recipes: [])
    }

    private static func line(_ item: PopoteServer.Inbox.Ingredient) -> IngredientLine {
        var line = IngredientParser.parse("\(Units.formatNumber(item.quantity)) \(item.unit) \(item.name)", guessed: true)
        line.name = item.name.prefix(1).uppercased() + item.name.dropFirst()
        line.gramsOverride = item.grams > 0 ? item.grams : nil
        line.estimate = EstimatedNutrition(kcal: item.kcal, protein: item.protein, carbs: item.carbs, fat: item.fat)
        return line
    }

    /// Shares the context only (no inbox), e.g. when leaving Popote for Claude: Claude then sees what was just logged.
    func shareContext(context: ModelContext, health: HealthService) async {
        guard token != nil else { return }
        do { try await api.putContext(makeContext(context, health: health)) } catch {
            log.error("shareContext: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func makeContext(_ context: ModelContext, health: HealthService) throws -> PopoteServer.Context {
        let pantry = try context.fetch(FetchDescriptor<PantryItem>()).map(\.name)
        let allRecipes = try context.fetch(FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\.title)]))
        let recipes = allRecipes.map(\.title)
        let start = Calendar.current.startOfDay(for: .now)
        let eaten = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date >= start }))
            .reduce(Nutrition.zero) { $0 + $1.nutrition }
        let targets = DailyTargets(health: health)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return PopoteServer.Context(
            language: Locale.current.language.languageCode?.identifier == "fr" ? "fr" : "en",
            timezone: TimeZone.current.identifier,
            today: formatter.string(from: .now),
            pantry: pantry,
            recipes: recipes,
            targets: .init(kcal: targets.kcal, protein: targets.protein, carbs: targets.carbs, fat: targets.fat),
            eaten: .init(kcal: eaten.kcal, protein: eaten.protein, carbs: eaten.carbs, fat: eaten.fat),
            goal: GoalSettings.current.title,
            journal: try journalItems(context, recipes: allRecipes),
            recipeDetails: allRecipes.map(Self.recipeItem))
    }

    /// The last 60 days of the journal, with the ingredients eaten when known.
    private func journalItems(_ context: ModelContext, recipes: [Recipe]) throws -> [PopoteServer.Context.JournalItem] {
        let since = Calendar.current.date(byAdding: .day, value: -60, to: Calendar.current.startOfDay(for: .now))!
        let entries = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date >= since }, sortBy: [SortDescriptor(\.date)]))
        let titles = Dictionary(recipes.map { ($0.id, $0.title) }, uniquingKeysWith: { a, _ in a })
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return entries.suffix(3000).map { entry in
            let lines = entry.lines
            return .init(date: formatter.string(from: entry.date), meal: entry.meal.rawValue, title: entry.title,
                         amount: entry.detail.isEmpty ? nil : entry.detail, recipe: entry.recipeID.flatMap { titles[$0] },
                         kcal: Self.tidy(entry.kcal), protein: Self.tidy(entry.protein), carbs: Self.tidy(entry.carbs), fat: Self.tidy(entry.fat),
                         ingredients: lines.isEmpty ? nil : lines.prefix(80).map(Self.ingredient))
        }
    }

    private static func recipeItem(_ recipe: Recipe) -> PopoteServer.Context.RecipeItem {
        let n = NutritionEngine.evaluate(recipe).perServing
        return .init(title: recipe.title, servings: recipe.servings, minutes: recipe.minutes, source: recipe.source.rawValue,
                     url: recipe.sourceURL.isEmpty ? nil : recipe.sourceURL,
                     createdAt: ISO8601DateFormatter().string(from: recipe.createdAt), inShoppingList: recipe.inShoppingList,
                     perServing: .init(kcal: tidy(n.kcal), protein: tidy(n.protein), carbs: tidy(n.carbs), fat: tidy(n.fat)),
                     ingredients: recipe.ingredients.prefix(80).map(ingredient),
                     steps: recipe.steps.prefix(60).map(\.text))
    }

    /// One decimal, never negative (the server rejects negative macros).
    private static func tidy(_ value: Double) -> Double { (max(value, 0) * 10).rounded() / 10 }

    private static func ingredient(_ line: IngredientLine) -> PopoteServer.Context.Ingredient {
        let item = NutritionEngine.evaluate(line)
        let product = line.product.map { [$0.brand, $0.name].compactMap { $0 }.joined(separator: " · ") }
        return .init(name: line.name.isEmpty ? line.raw : line.name, quantity: line.quantity, unit: line.unit,
                     grams: item.grams.map { ($0 * 10).rounded() / 10 }, kcal: line.ignored ? nil : item.nutrition.kcal.rounded(), product: product)
    }
}
