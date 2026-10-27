import Foundation

/// Reads a schema.org/Recipe block (Marmiton, CuisineAZ, BBC Good Food, NYT Cooking…).
enum JSONLDRecipe {
    static func find(in blocks: [Any]) -> [String: Any]? {
        for block in blocks {
            if let recipe = search(block) { return recipe }
        }
        return nil
    }

    private static func search(_ node: Any) -> [String: Any]? {
        if let array = node as? [Any] {
            for item in array { if let found = search(item) { return found } }
        } else if let object = node as? [String: Any] {
            if isRecipe(object["@type"]) { return object }
            if let graph = object["@graph"] { return search(graph) }
            if let main = object["mainEntity"] { return search(main) }
        }
        return nil
    }

    private static func isRecipe(_ type: Any?) -> Bool {
        if let type = type as? String { return type == "Recipe" || type.hasSuffix("/Recipe") }
        if let types = type as? [String] { return types.contains("Recipe") }
        return false
    }

    static func parse(_ object: [String: Any], url: URL) -> ImportedRecipe {
        var recipe = ImportedRecipe(source: .web, url: url.absoluteString)
        recipe.title = text(object["name"]) ?? ""
        recipe.author = author(object["author"]) ?? url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        recipe.imageURL = image(object["image"])
        recipe.servings = servings(object["recipeYield"])
        recipe.minutes = minutes(object["totalTime"]) ?? {
            let sum = (minutes(object["prepTime"]) ?? 0) + (minutes(object["cookTime"]) ?? 0)
            return sum > 0 ? sum : nil
        }()
        recipe.ingredients = strings(object["recipeIngredient"] ?? object["ingredients"]).map { IngredientParser.parse($0) }
        recipe.steps = instructions(object["recipeInstructions"]).map { RecipeStep(text: $0) }
        if let video = object["video"] as? [String: Any] ?? (object["video"] as? [[String: Any]])?.first,
           let embed = text(video["embedUrl"]) ?? text(video["contentUrl"]),
           let embedURL = URL(string: embed), let id = SourceDetector.youTubeID(embedURL) {
            recipe.videoID = id
        }
        return recipe
    }

    private static func text(_ value: Any?) -> String? {
        if let string = value as? String { return HTML.decodeEntities(string).trimmingCharacters(in: .whitespacesAndNewlines) }
        if let array = value as? [Any] { return text(array.first) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func strings(_ value: Any?) -> [String] {
        if let array = value as? [Any] { return array.compactMap { text($0) }.filter { !$0.isEmpty } }
        if let string = value as? String {
            return string.components(separatedBy: .newlines).map { HTML.decodeEntities($0) }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return []
    }

    private static func author(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] { return text(object["name"]) }
        if let array = value as? [Any] { return author(array.first) }
        return nil
    }

    private static func image(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let object = value as? [String: Any] { return text(object["url"]) ?? text(object["contentUrl"]) }
        if let array = value as? [Any] {
            // Prefer the widest image when sizes are given.
            let objects = array.compactMap { $0 as? [String: Any] }
            if let widest = objects.max(by: { ($0["width"] as? Int ?? 0) < ($1["width"] as? Int ?? 0) }) { return image(widest) }
            return image(array.first)
        }
        return nil
    }

    private static func servings(_ value: Any?) -> Int {
        if let number = value as? NSNumber { return max(number.intValue, 1) }
        if let string = value as? String, let match = string.firstMatch(of: /(\d+)/) { return max(Int(match.1) ?? 2, 1) }
        if let array = value as? [Any] {
            for item in array { let n = servings(item); if n > 1 { return n } }
        }
        return 2
    }

    /// ISO 8601 duration: "PT1H15M" → 75.
    static func minutes(_ value: Any?) -> Int? {
        guard let string = value as? String, let match = string.firstMatch(of: /P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?/) else { return nil }
        let days = match.1.flatMap { Int($0) } ?? 0
        let hours = match.2.flatMap { Int($0) } ?? 0
        let mins = match.3.flatMap { Int($0) } ?? 0
        let total = days * 1440 + hours * 60 + mins
        return total > 0 ? total : nil
    }

    private static func instructions(_ value: Any?) -> [String] {
        if let string = value as? String {
            return HTML.text(string).components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        guard let array = value as? [Any] else { return [] }
        return array.flatMap { item -> [String] in
            if let string = item as? String { return instructions(string) }
            guard let object = item as? [String: Any] else { return [] }
            if let elements = object["itemListElement"] { return instructions(elements) }   // HowToSection
            return [text(object["text"]) ?? text(object["name"])].compactMap { $0.map { HTML.text($0) } }
        }
    }
}
