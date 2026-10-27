import Foundation

/// One line of the merged shopping list.
struct ShoppingItem: Identifiable, Hashable {
    var id: String { key }
    let key: String                  // FoodTable id or normalized name
    let name: String
    var grams: Double = 0            // mass and volume are summed in g / ml
    var millilitres: Double = 0
    var pieces: Double = 0
    var unitless = false             // "salt, to taste"
    var aisle: Aisle
    var recipes: [String] = []

    /// "600 g", "2", "1 l", "3 + 200 g"
    var quantity: String {
        var parts: [String] = []
        if pieces > 0 { parts.append(Units.formatNumber(pieces)) }
        if grams > 0 { parts.append(grams >= 1000 ? "\(Units.formatNumber(grams / 1000)) kg" : "\(Int(grams.rounded())) g") }
        if millilitres > 0 { parts.append(millilitres >= 1000 ? "\(Units.formatNumber(millilitres / 1000)) l" : "\(Int(millilitres.rounded())) ml") }
        return parts.joined(separator: " + ")
    }
}

enum ShoppingList {
    static func build(recipes: [Recipe], pantryKeys: Set<String>) -> (toBuy: [ShoppingItem], inPantry: [ShoppingItem]) {
        var items: [String: ShoppingItem] = [:]
        for recipe in recipes {
            let factor = Double(recipe.shoppingServings) / Double(max(recipe.servings, 1))
            for line in recipe.ingredients where !line.ignored {
                let food = NutritionEngine.food(for: line)
                if food?.staple == true { continue }
                let key = food?.id ?? TextKey.key(line.name)
                guard !key.isEmpty else { continue }
                var item = items[key] ?? ShoppingItem(key: key, name: food?.name ?? line.name, aisle: food?.aisle ?? .other)
                if !item.recipes.contains(recipe.title) { item.recipes.append(recipe.title) }
                let unit = Units.unit(line.unit)
                if let quantity = line.quantity.map({ $0 * factor }) {
                    if let g = unit?.grams, line.unit != "pinch" {
                        item.grams += quantity * g
                    } else if let ml = unit?.millilitres, ["l", "dl", "cl", "ml"].contains(line.unit) {
                        item.millilitres += quantity * ml
                    } else if line.unit == "piece" || line.unit == nil || line.unit == "clove" {
                        item.pieces += quantity
                    } else if let grams = NutritionEngine.grams(for: line, food: food) {
                        item.grams += grams * factor                                  // spoons, cups → grams
                    } else {
                        item.pieces += quantity
                    }
                } else {
                    item.unitless = true
                }
                items[key] = item
            }
        }
        let sorted = items.values.sorted {
            $0.aisle == $1.aisle ? $0.name.localizedCompare($1.name) == .orderedAscending
                : Aisle.allCases.firstIndex(of: $0.aisle)! < Aisle.allCases.firstIndex(of: $1.aisle)!
        }
        return (sorted.filter { !pantryKeys.contains($0.key) }, sorted.filter { pantryKeys.contains($0.key) })
    }

    /// Plain text, for Reminders, Notes or a message.
    static func text(_ items: [ShoppingItem]) -> String {
        Dictionary(grouping: items, by: \.aisle)
            .sorted { Aisle.allCases.firstIndex(of: $0.key)! < Aisle.allCases.firstIndex(of: $1.key)! }
            .map { aisle, items in
                aisle.name + "\n" + items.map { "• \($0.name)\($0.quantity.isEmpty ? "" : " — \($0.quantity)")" }.joined(separator: "\n")
            }
            .joined(separator: "\n\n")
    }
}
