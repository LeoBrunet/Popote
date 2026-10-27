import Foundation
import SwiftData
import SwiftUI

enum RecipeSource: String, Codable, CaseIterable {
    case youtube, instagram, tiktok, web, manual, claude

    var name: String {
        switch self {
        case .youtube: "YouTube"
        case .instagram: "Instagram"
        case .tiktok: "TikTok"
        case .web: "Web"
        case .manual: String(localized: "Manual")
        case .claude: "Claude"
        }
    }

    var icon: String {
        switch self {
        case .youtube: "play.rectangle.fill"
        case .instagram: "camera.fill"
        case .tiktok: "music.note"
        case .web: "globe"
        case .manual: "pencil"
        case .claude: "sparkle"
        }
    }

    var color: Color {
        switch self {
        case .youtube: Color(red: 0.93, green: 0.13, blue: 0.13)
        case .instagram: Color(red: 0.80, green: 0.22, blue: 0.55)
        case .tiktok: Color(red: 0.10, green: 0.10, blue: 0.12)
        case .web: Color(red: 0.25, green: 0.45, blue: 0.75)
        case .manual: Color.gray
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    var hasVideo: Bool { self == .youtube || self == .instagram || self == .tiktok }
}

/// One ingredient line of a recipe, as parsed from the source, plus the nutrition match the user confirmed.
struct IngredientLine: Codable, Hashable, Identifiable {
    var id = UUID()
    var raw: String
    var name: String
    var quantity: Double?
    var unit: String?               // normalized unit key, see `Units`
    var guessed = false             // structured from free text: worth a check
    var foodID: String?             // FoodTable match picked by the user
    var product: ProductSnapshot?   // or a scanned product
    var gramsOverride: Double?      // weight typed by the user
    var ignored = false             // counted as 0 kcal (water, salt…)
    var estimate: EstimatedNutrition?   // Claude's estimate for this line, used when no food matches

    /// The same ingredient for `factor` times the amount (servings eaten vs. the recipe's).
    func scaled(by factor: Double) -> IngredientLine {
        guard factor != 1 else { return self }
        var line = self
        line.quantity = quantity.map { $0 * factor }
        line.gramsOverride = gramsOverride.map { $0 * factor }
        line.estimate = estimate.map { EstimatedNutrition(kcal: $0.kcal * factor, protein: $0.protein * factor, carbs: $0.carbs * factor, fat: $0.fat * factor) }
        if let q = line.quantity, !name.isEmpty {
            line.raw = "\(Units.format(q, unit: unit)) \(name)".trimmingCharacters(in: .whitespaces)
        }
        return line
    }
}

/// Nutrition of one ingredient line as estimated by Claude (for the line's amount, not per 100 g).
struct EstimatedNutrition: Codable, Hashable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

struct RecipeStep: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var timestamp: Int?             // seconds into the video
}

/// Nutrition of a packaged product (Open Food Facts), per 100 g.
struct ProductSnapshot: Codable, Hashable {
    var code: String
    var name: String
    var brand: String?
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var nutriScore: String?
    var servingGrams: Double?
    var imageURL: String?
}

@Model
final class Recipe {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var sourceRaw: String = RecipeSource.web.rawValue
    var sourceURL: String = ""
    var videoID: String?
    var imageURL: String?
    @Attribute(.externalStorage) var imageData: Data?
    var minutes: Int?
    var servings: Int = 2
    var ingredientsData: Data = Data()
    var stepsData: Data = Data()
    var rawText: String?
    var createdAt: Date = Date()
    var needsReview: Bool = false
    var inShoppingList: Bool = false
    var shoppingServings: Int = 2

    init(title: String, source: RecipeSource, url: String = "") {
        self.title = title
        self.sourceRaw = source.rawValue
        self.sourceURL = url
    }

    var source: RecipeSource {
        get { RecipeSource(rawValue: sourceRaw) ?? .web }
        set { sourceRaw = newValue.rawValue }
    }

    var ingredients: [IngredientLine] {
        get { (try? JSONDecoder().decode([IngredientLine].self, from: ingredientsData)) ?? [] }
        set { ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var steps: [RecipeStep] {
        get { (try? JSONDecoder().decode([RecipeStep].self, from: stepsData)) ?? [] }
        set { stepsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

enum Meal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner
    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .snack: "Snack"
        case .dinner: "Dinner"
        }
    }

    var icon: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .snack: "carrot.fill"
        case .dinner: "moon.stars.fill"
        }
    }

    /// Meal that fits the current time of day.
    static var now: Meal {
        switch Calendar.current.component(.hour, from: .now) {
        case ..<11: .breakfast
        case ..<15: .lunch
        case ..<18: .snack
        default: .dinner
        }
    }
}

@Model
final class JournalEntry {
    var id: UUID = UUID()
    var date: Date = Date()
    var mealRaw: String = Meal.lunch.rawValue
    var title: String = ""
    var detail: String = ""
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var recipeID: UUID?
    var healthUUID: String?
    var amount: Double?             // servings or grams logged, to rescale when edited
    var amountUnit: String?         // "serving" or "g"
    var linesData: Data = Data()    // ingredients as eaten (recipes, Claude meals), editable afterwards

    init(date: Date, meal: Meal, title: String, detail: String, nutrition: Nutrition) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.title = title
        self.detail = detail
        self.kcal = nutrition.kcal
        self.protein = nutrition.protein
        self.carbs = nutrition.carbs
        self.fat = nutrition.fat
    }

    var meal: Meal {
        get { Meal(rawValue: mealRaw) ?? .lunch }
        set { mealRaw = newValue.rawValue }
    }

    func setAmount(_ value: Double, unit: String) {
        amount = value
        amountUnit = unit
        detail = unit == "g" ? "\(Int(value.rounded())) g" : Units.servings(value)
    }
    var nutrition: Nutrition { Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }

    var lines: [IngredientLine] {
        get { linesData.isEmpty ? [] : (try? JSONDecoder().decode([IngredientLine].self, from: linesData)) ?? [] }
        set { linesData = newValue.isEmpty ? Data() : (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class PantryItem {
    var name: String = ""
    var key: String = ""                    // FoodTable id or normalized name
    var addedAt: Date = Date()

    init(name: String, key: String) {
        self.name = name
        self.key = key
    }
}

/// A ticked line of the shopping list.
@Model
final class ShoppingCheck {
    var key: String = ""
    init(key: String) { self.key = key }
}
