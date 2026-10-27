import Foundation

/// How sure we are about one ingredient's nutrition.
enum MatchKind: Equatable {
    case product(String)      // scanned / picked packaged product
    case food(String)         // generic food confirmed by the user
    case estimated(String)    // generic food matched automatically
    case ignored
    case missing              // no food, or no way to know the weight
}

struct IngredientNutrition {
    let line: IngredientLine
    let kind: MatchKind
    let grams: Double?
    let nutrition: Nutrition
    let food: Food?
}

enum NutritionEngine {
    static func food(for line: IngredientLine) -> Food? {
        if let id = line.foodID { return FoodTable.byID[id] }
        return FoodTable.match(line.name)
    }

    /// Weight of an ingredient line in grams, when it can be known.
    static func grams(for line: IngredientLine, food: Food?, productServing: Double? = nil) -> Double? {
        if let override = line.gramsOverride { return override }
        let quantity = line.quantity ?? (line.unit == nil ? nil : 1)
        let unit = Units.unit(line.unit)
        switch line.unit {
        case "clove":
            return (quantity ?? 1) * (food?.id == "garlic" ? 5 : (food?.pieceGrams ?? 5))
        case "slice":
            return (quantity ?? 1) * (food?.pieceGrams.map { min($0, 40) } ?? 30)
        case "sachet":
            return (quantity ?? 1) * (food?.pieceGrams ?? productServing ?? 10)
        case "piece", nil:
            guard let quantity else { return nil }
            if let serving = productServing { return quantity * serving }
            return food?.pieceGrams.map { quantity * $0 }
        default:
            guard let unit, let quantity else { return nil }
            if let g = unit.grams { return quantity * g }
            if let ml = unit.millilitres { return quantity * ml * (food?.density ?? 1) }
            return nil
        }
    }

    static func evaluate(_ line: IngredientLine) -> IngredientNutrition {
        if line.ignored {
            return IngredientNutrition(line: line, kind: .ignored, grams: nil, nutrition: .zero, food: nil)
        }
        if let product = line.product {
            let grams = grams(for: line, food: nil, productServing: product.servingGrams)
            let per100 = Nutrition(kcal: product.kcal, protein: product.protein, carbs: product.carbs, fat: product.fat)
            guard let grams else {
                return IngredientNutrition(line: line, kind: .missing, grams: nil, nutrition: .zero, food: nil)
            }
            return IngredientNutrition(line: line, kind: .product(product.name), grams: grams, nutrition: per100 * (grams / 100), food: nil)
        }
        let food = food(for: line)
        // Claude saw the actual dish (cooked weights, sauces…): its estimate wins unless the user picked a food.
        if let estimate = line.estimate, line.foodID == nil {
            let nutrition = Nutrition(kcal: estimate.kcal, protein: estimate.protein, carbs: estimate.carbs, fat: estimate.fat)
            return IngredientNutrition(line: line, kind: .estimated("Claude"), grams: line.gramsOverride, nutrition: nutrition, food: food)
        }
        guard let food else {
            return IngredientNutrition(line: line, kind: .missing, grams: nil, nutrition: .zero, food: nil)
        }
        if food.staple && line.quantity == nil {
            return IngredientNutrition(line: line, kind: .ignored, grams: nil, nutrition: .zero, food: food)
        }
        guard let grams = grams(for: line, food: food) else {
            return IngredientNutrition(line: line, kind: .missing, grams: nil, nutrition: .zero, food: food)
        }
        let kind: MatchKind = line.foodID != nil ? .food(food.name) : .estimated(food.name)
        return IngredientNutrition(line: line, kind: kind, grams: grams, nutrition: food.per100g * (grams / 100), food: food)
    }

    struct RecipeNutrition {
        let total: Nutrition
        let perServing: Nutrition
        let lines: [IngredientNutrition]
        var missing: Int { lines.filter { $0.kind == .missing }.count }
        var verified: Int {
            lines.filter { if case .product = $0.kind { true } else if case .food = $0.kind { true } else { false } }.count
        }
    }

    static func evaluate(_ recipe: Recipe) -> RecipeNutrition {
        let lines = recipe.ingredients.map(evaluate)
        let total = lines.reduce(Nutrition.zero) { $0 + $1.nutrition }
        return RecipeNutrition(total: total, perServing: total / Double(max(recipe.servings, 1)), lines: lines)
    }
}
