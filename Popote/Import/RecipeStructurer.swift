import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Free text (caption, video description) → ingredients + steps.
/// Apple's on-device model when available (iOS 26, Apple Intelligence on), rules otherwise.
enum RecipeStructurer {
    struct Result {
        var title: String?
        var servings: Int?
        var minutes: Int?
        var ingredients: [IngredientLine]
        var steps: [RecipeStep]
    }

    static func structure(_ text: String) async -> Result {
        let rules = parse(text)
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), rules.ingredients.count < 3 || rules.steps.isEmpty,
           let model = try? await withModel(text) {
            // Keep the timestamps the rules found in video descriptions.
            var result = model
            if result.steps.allSatisfy({ $0.timestamp == nil }), rules.steps.count == result.steps.count {
                result.steps = zip(result.steps, rules.steps).map { RecipeStep(text: $0.text, timestamp: $1.timestamp) }
            }
            return result
        }
        #endif
        return rules
    }

    // MARK: Rules

    private static let ingredientHeaders = /^(ingr[ée]dients?|ingredients?|liste des courses|il vous faut|you'?ll need|what you need|for the [\w\s]+|pour (?:la|le|les) [\w\s]+)\s*(\(.*\))?\s*:?\s*$/
    private static let stepHeaders = /^(pr[ée]paration|instructions?|[ée]tapes?|recette|method|steps?|directions?|how to( make)?( it)?|d[ée]roul[ée]|cuisson)\s*:?\s*$/

    static func parse(_ text: String) -> Result {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var ingredients: [IngredientLine] = []
        var steps: [RecipeStep] = []
        var section = 0   // 0 unknown, 1 ingredients, 2 steps

        for line in lines {
            let cleaned = IngredientParser.clean(line)
            let lower = cleaned.lowercased()
            if lower.firstMatch(of: ingredientHeaders) != nil { section = 1; continue }
            if lower.firstMatch(of: stepHeaders) != nil { section = 2; continue }
            if cleaned.hasPrefix("#") || cleaned.hasPrefix("@") || cleaned.contains("http") { continue }

            // Chapters / timestamps in video descriptions: "2:15 Cuisson du riz"
            var timestamp: Int?
            var body = cleaned
            if let match = cleaned.firstMatch(of: /^\(?(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\)?\s*[-–:]?\s*(.+)$/) {
                timestamp = (match.1.flatMap { Int($0) } ?? 0) * 3600 + (Int(match.2) ?? 0) * 60 + (Int(match.3) ?? 0)
                body = String(match.4)
            }
            let numbered = body.firstMatch(of: /^(?:\d{1,2}|[a-z])\s*[.)]\s+(.+)$/).map { String($0.1) }
            let isIngredient = IngredientParser.looksLikeIngredient(body) && numbered == nil

            switch section {
            case 1 where isIngredient || body.count < 60:
                if timestamp == nil, body.count < 90 { ingredients.append(IngredientParser.parse(body, guessed: true)) }
            case 2:
                steps.append(RecipeStep(text: numbered ?? body, timestamp: timestamp))
            default:
                if isIngredient && timestamp == nil {
                    ingredients.append(IngredientParser.parse(body, guessed: true))
                    if section == 2 { section = 1 }
                } else if let numbered {
                    steps.append(RecipeStep(text: numbered, timestamp: timestamp))
                } else if timestamp != nil || (body.count > 40 && !ingredients.isEmpty) {
                    steps.append(RecipeStep(text: body, timestamp: timestamp))
                }
            }
        }
        return Result(title: nil, servings: servings(text), minutes: minutes(text), ingredients: ingredients, steps: steps)
    }

    static func servings(_ text: String) -> Int? {
        let lower = text.lowercased()
        let patterns = [/pour (\d+) (?:personnes?|pers|portions?|parts?)/, /(\d+) (?:personnes|portions|servings|parts)/, /serves (\d+)/]
        for pattern in patterns {
            if let match = lower.firstMatch(of: pattern), let n = Int(match.1), (1...20).contains(n) { return n }
        }
        return nil
    }

    static func minutes(_ text: String) -> Int? {
        let lower = text.lowercased()
        if let match = lower.firstMatch(of: /(?:total|temps|time|ready in|prêt en)[^\d]{0,15}(\d+)\s*(?:min|minutes)/), let n = Int(match.1) { return n }
        if let match = lower.firstMatch(of: /(\d+)\s*h\s*(\d+)?/), let h = Int(match.1), h < 6 {
            return h * 60 + (match.2.flatMap { Int($0) } ?? 0)
        }
        if let match = lower.firstMatch(of: /en (\d+)\s*min/), let n = Int(match.1) { return n }
        return nil
    }

    // MARK: On-device model

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct GeneratedRecipe {
        @Guide(description: "Short recipe title, in the language of the text")
        var title: String
        @Guide(description: "Number of servings, 0 if not stated")
        var servings: Int
        @Guide(description: "Every ingredient with its quantity, as written in the text")
        var ingredients: [GeneratedIngredient]
        @Guide(description: "Preparation steps in order, one action per step, in the language of the text")
        var steps: [String]
    }

    @available(iOS 26.0, *)
    @Generable
    struct GeneratedIngredient {
        @Guide(description: "Quantity as a number, 0 if not stated")
        var quantity: Double
        @Guide(description: "Unit as written (g, ml, c. à soupe, tbsp, cup…), empty if none")
        var unit: String
        @Guide(description: "Ingredient name, without the quantity")
        var name: String
    }

    @available(iOS 26.0, *)
    private static func withModel(_ text: String) async throws -> Result? {
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: """
            You extract recipes from social media captions and video descriptions. \
            Only use information present in the text. Never invent ingredients or quantities.
            """)
        let prompt = "Extract the recipe from this text:\n\n" + String(text.prefix(3500))
        let generated = try await session.respond(to: prompt, generating: GeneratedRecipe.self).content
        guard !generated.ingredients.isEmpty else { return nil }
        let ingredients = generated.ingredients.map { item -> IngredientLine in
            let quantity = item.quantity > 0 ? Units.formatNumber(item.quantity) + " " : ""
            return IngredientParser.parse(quantity + (item.unit.isEmpty ? "" : item.unit + " ") + item.name, guessed: true)
        }
        return Result(title: generated.title, servings: generated.servings > 0 ? generated.servings : nil, minutes: minutes(text),
                      ingredients: ingredients, steps: generated.steps.map { RecipeStep(text: $0) })
    }
    #endif
}
