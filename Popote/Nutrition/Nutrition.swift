import Foundation

struct Nutrition: Hashable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static let zero = Nutrition()

    static func + (a: Nutrition, b: Nutrition) -> Nutrition {
        Nutrition(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
    }

    static func * (a: Nutrition, k: Double) -> Nutrition {
        Nutrition(kcal: a.kcal * k, protein: a.protein * k, carbs: a.carbs * k, fat: a.fat * k)
    }

    static func / (a: Nutrition, k: Double) -> Nutrition { a * (1 / max(k, 0.0001)) }
}

/// Lowercased, accent-free, singular words: "Œufs frais" → "oeuf frai".
enum TextKey {
    private static let stopwords: Set<String> = [
        "de", "d", "du", "des", "la", "le", "les", "l", "a", "au", "aux", "en", "et", "ou", "un", "une",
        "of", "the", "and", "or", "for", "to", "in", "with", "avec", "pour", "sans",
        "fresh", "gros", "grosse", "petit", "petite", "small", "large", "big", "medium", "moyen", "moyenne",
        "hache", "hachee", "haches", "chopped", "minced", "emince", "emincee", "sliced", "diced", "coupe", "coupee", "cubes",
        "bio", "organic", "environ", "about", "optional", "facultatif", "bien", "mur", "mure", "ripe",
    ]

    static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
    }

    static func words(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopwords.contains($0) && Double($0) == nil }
            .map(singular)
    }

    static func key(_ text: String) -> String { words(text).joined(separator: " ") }

    static func singular(_ word: String) -> String {
        guard word.count > 3 else { return word }
        if word.hasSuffix("oes") { return String(word.dropLast(2)) }        // tomatoes → tomato
        if word.hasSuffix("ies") { return String(word.dropLast(3)) + "y" }  // berries → berry
        if word.hasSuffix("s") || word.hasSuffix("x") { return String(word.dropLast()) }
        return word
    }
}

/// Units an ingredient quantity can be expressed in, and how to turn them into grams.
enum Units {
    struct Unit {
        let key: String
        let labels: [String]       // as written in recipes, longest first when matching
        let grams: Double?         // fixed mass (g, kg, oz…)
        let millilitres: Double?   // volume, converted with the food's density
    }

    static let all: [Unit] = [
        Unit(key: "kg", labels: ["kilogrammes", "kilogramme", "kilos", "kilo", "kg"], grams: 1000, millilitres: nil),
        Unit(key: "g", labels: ["grammes", "gramme", "grams", "gram", "gr", "g"], grams: 1, millilitres: nil),
        Unit(key: "mg", labels: ["mg"], grams: 0.001, millilitres: nil),
        Unit(key: "lb", labels: ["pounds", "pound", "lbs", "lb"], grams: 453.6, millilitres: nil),
        Unit(key: "oz", labels: ["ounces", "ounce", "oz"], grams: 28.35, millilitres: nil),
        Unit(key: "l", labels: ["litres", "litre", "liters", "liter", "l"], grams: nil, millilitres: 1000),
        Unit(key: "dl", labels: ["dl"], grams: nil, millilitres: 100),
        Unit(key: "cl", labels: ["cl"], grams: nil, millilitres: 10),
        Unit(key: "ml", labels: ["millilitres", "ml"], grams: nil, millilitres: 1),
        Unit(key: "tbsp", labels: ["cuillères à soupe", "cuillère à soupe", "cuilleres a soupe", "cuillere a soupe", "c. à soupe", "c.à soupe",
                                   "c à soupe", "c. a soupe", "c.a.s", "cas", "càs", "cs", "tablespoons", "tablespoon", "tbsp", "tbs", "el"],
             grams: nil, millilitres: 15),
        Unit(key: "tsp", labels: ["cuillères à café", "cuillère à café", "cuilleres a cafe", "cuillere a cafe", "c. à café", "c.à café",
                                  "c à café", "c. a cafe", "c.a.c", "cac", "càc", "cc", "teaspoons", "teaspoon", "tsp", "tl"],
             grams: nil, millilitres: 5),
        Unit(key: "cup", labels: ["cups", "cup", "tasses", "tasse", "bols", "bol"], grams: nil, millilitres: 240),
        Unit(key: "pinch", labels: ["pincées", "pincée", "pincees", "pincee", "pinches", "pinch"], grams: 0.5, millilitres: nil),
        Unit(key: "clove", labels: ["gousses", "gousse", "cloves", "clove"], grams: nil, millilitres: nil),
        Unit(key: "slice", labels: ["tranches", "tranche", "slices", "slice"], grams: nil, millilitres: nil),
        Unit(key: "can", labels: ["boîtes", "boîte", "boites", "boite", "cans", "can", "conserves", "conserve"], grams: 400, millilitres: nil),
        Unit(key: "bunch", labels: ["bottes", "botte", "bouquets", "bouquet", "bunches", "bunch"], grams: 50, millilitres: nil),
        Unit(key: "handful", labels: ["poignées", "poignée", "poignees", "poignee", "handfuls", "handful"], grams: 30, millilitres: nil),
        Unit(key: "sachet", labels: ["sachets", "sachet", "packets", "packet", "paquets", "paquet"], grams: nil, millilitres: nil),
        Unit(key: "piece", labels: ["pièces", "pièce", "pieces", "piece", "pcs"], grams: nil, millilitres: nil),
    ]

    static func unit(_ key: String?) -> Unit? { all.first { $0.key == key } }

    /// Short label shown next to a quantity.
    static func label(_ key: String?, quantity: Double) -> String {
        let plural = quantity > 1
        switch key {
        case nil, "piece": return ""
        case "tbsp": return String(localized: "tbsp")
        case "tsp": return String(localized: "tsp")
        case "cup": return plural ? String(localized: "cups") : String(localized: "cup")
        case "pinch": return plural ? String(localized: "pinches") : String(localized: "pinch")
        case "clove": return plural ? String(localized: "cloves") : String(localized: "clove")
        case "slice": return plural ? String(localized: "slices") : String(localized: "slice")
        case "can": return plural ? String(localized: "cans") : String(localized: "can")
        case "bunch": return plural ? String(localized: "bunches") : String(localized: "bunch")
        case "handful": return plural ? String(localized: "handfuls") : String(localized: "handful")
        case "sachet": return plural ? String(localized: "packets") : String(localized: "packet")
        case let other?: return other
        }
    }

    static func format(_ quantity: Double?, unit: String?) -> String {
        guard let quantity else { return "" }
        let number = formatNumber(quantity)
        let label = label(unit, quantity: quantity)
        if label.isEmpty { return number }
        return "\(number) \(label)"
    }

    /// "½ serving", "1 serving", "2 servings"
    static func servings(_ value: Double) -> String {
        let number = formatNumber(value)
        return value <= 1 ? String(localized: "\(number) serving") : String(localized: "\(number) servings")
    }

    static func formatNumber(_ value: Double) -> String {
        let fractions: [(Double, String)] = [(0.25, "¼"), (0.5, "½"), (0.75, "¾"), (1.0 / 3, "⅓"), (2.0 / 3, "⅔")]
        let whole = value.rounded(.down)
        let rest = value - whole
        if value < 10, let fraction = fractions.first(where: { abs($0.0 - rest) < 0.04 }) {
            return whole == 0 ? fraction.1 : "\(Int(whole))\(fraction.1)"
        }
        if value >= 10 { return "\(Int(value.rounded()))" }
        if abs(rest) < 0.05 { return "\(Int(whole))" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
