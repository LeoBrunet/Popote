import Foundation
import OSLog
import SwiftData

/// Journal entries logged by weight before meals kept their ingredients (a scanned product or a food)
/// only have a title, a weight and totals. Rebuild their single ingredient so they can be edited, reused
/// in recipes ("My products") and read by Claude. The values per 100 g come back exactly from totals ÷ weight.
enum JournalBackfill {
    private static let doneKey = "journalLinesBackfilled.v2"

    @MainActor
    static func run(context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        let entries: [JournalEntry]
        do { entries = try context.fetch(FetchDescriptor<JournalEntry>()) } catch {
            Logger(subsystem: "com.leobrunet.popote", category: "backfill").error("fetch: \(error.localizedDescription, privacy: .public)")
            return
        }
        for entry in entries where entry.linesData.isEmpty && entry.recipeID == nil && entry.amountUnit == "g" {
            guard let grams = entry.amount, grams > 0, let line = line(for: entry, grams: grams) else { continue }
            entry.lines = [line]
        }
        try? context.save()
        UserDefaults.standard.set(true, forKey: doneKey)
    }

    private static func line(for entry: JournalEntry, grams: Double) -> IngredientLine? {
        let title = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let per100 = entry.nutrition * (100 / grams)
        // A generic food logged by weight: same name and same calories as the table.
        if let food = FoodTable.all.first(where: { [$0.en, $0.fr].contains { $0.caseInsensitiveCompare(title) == .orderedSame } }),
           abs(food.per100g.kcal - per100.kcal) <= max(1, food.per100g.kcal * 0.02) {
            return IngredientLine(raw: "\(Units.formatNumber(grams)) g \(food.name)", name: food.name, quantity: grams, unit: "g",
                                  foodID: food.id, gramsOverride: grams)
        }
        // A scanned product, titled "Brand · Name" (or just "Name"). The barcode wasn't kept: the title stands in for it.
        let parts = title.components(separatedBy: " · ")
        let brand = parts.count > 1 ? parts[0] : nil
        let name = parts.count > 1 ? parts.dropFirst().joined(separator: " · ") : title
        let product = ProductSnapshot(code: "journal:\(TextKey.key(title))", name: name, brand: brand,
                                      kcal: per100.kcal, protein: per100.protein, carbs: per100.carbs, fat: per100.fat)
        return IngredientLine(raw: "\(Units.formatNumber(grams)) g \(name)", name: name, quantity: grams, unit: "g",
                              product: product, gramsOverride: grams)
    }
}
