import Foundation

/// Turns "2 c. à soupe de miso blanc" / "1 ½ cups flour" / "Farine : 200 g" into quantity + unit + name.
enum IngredientParser {
    private static let unicodeFractions: [Character: Double] = ["½": 0.5, "¼": 0.25, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3, "⅛": 0.125]
    private static let wordNumbers: [String: Double] = [
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "demi": 0.5, "demie": 0.5,
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "half": 0.5,
    ]

    /// Unit labels, longest first so "c. à soupe" wins over "c".
    private static let unitLabels: [(label: String, key: String)] = Units.all
        .flatMap { unit in unit.labels.map { ($0, unit.key) } }
        .sorted { $0.0.count > $1.0.count }

    static func parse(_ raw: String, guessed: Bool = false) -> IngredientLine {
        var text = clean(raw)
        var quantity: Double?
        var unit: String?

        // "Farine : 200 g" / "flour 200g"
        if let match = text.firstMatch(of: /^(?<name>[^[0-9]½¼¾⅓⅔]+?)\s*[:\-–]?\s*(?<qty>[0-9]+(?:[.,][0-9]+)?)\s*(?<unit>kg|g|gr|ml|cl|dl|l)\.?$/.ignoresCase()) {
            return IngredientLine(raw: raw, name: tidyName(String(match.name)), quantity: number(String(match.qty)),
                                  unit: unitKey(String(match.unit)), guessed: guessed)
        }

        // Leading quantity: "2", "1,5", "1/2", "½", "1 ½", "2-3", "2 x 130"
        if let match = text.firstMatch(of: /^(?<a>[0-9]+(?:[.,][0-9]+)?)\s*(?:[x×]\s*(?<b>[0-9]+(?:[.,][0-9]+)?))?/) {
            var value = number(String(match.a)) ?? 1
            text = String(text[match.range.upperBound...])
            if let b = match.b { value *= number(String(b)) ?? 1 }
            if let fraction = text.firstMatch(of: /^\s*\/\s*(?<d>[0-9]+)/) {           // 1/2
                value /= max(number(String(fraction.d)) ?? 1, 1)
                text = String(text[fraction.range.upperBound...])
            } else if let first = text.trimmingCharacters(in: .whitespaces).first, let f = unicodeFractions[first] {   // 1 ½
                value += f
                text = String(text.trimmingCharacters(in: .whitespaces).dropFirst())
            }
            if let range = text.firstMatch(of: /^\s*(?:-|–|à|to)\s*[0-9]+(?:[.,][0-9]+)?/) {   // 2-3 → 2
                text = String(text[range.range.upperBound...])
            }
            quantity = value
        } else if let first = text.first, let f = unicodeFractions[first] {
            quantity = f
            text = String(text.dropFirst())
        } else {
            let firstWord = text.split(separator: " ").first.map { $0.lowercased() } ?? ""
            if let value = wordNumbers[firstWord] {
                quantity = value
                text = String(text.dropFirst(firstWord.count))
            }
        }
        text = text.trimmingCharacters(in: .whitespaces)

        // Unit right after the quantity
        let lower = text.lowercased()
        for (label, key) in unitLabels {
            guard lower.hasPrefix(label) else { continue }
            let after = lower.dropFirst(label.count)
            guard after.isEmpty || after.first == " " || after.first == "." || after.first == "'" || after.first == "’" else { continue }
            unit = key
            text = String(text.dropFirst(label.count))
            if text.hasPrefix(".") { text.removeFirst() }
            break
        }
        if quantity != nil && unit == nil { unit = "piece" }

        // "(200 g)" written after the name gives the real weight
        var name = tidyName(text)
        var grams: Double?
        if let match = name.firstMatch(of: /\(\s*(?:env\.?\s*|about\s*|~\s*)?(?<g>[0-9]+(?:[.,][0-9]+)?)\s*(?<u>g|kg|ml|cl)\s*\)/.ignoresCase()) {
            if let value = number(String(match.g)) {
                let factors: [String: Double] = ["kg": 1000, "cl": 10]
                let factor: Double = factors[String(match.u).lowercased()] ?? 1
                let count: Double = unit == "piece" || unit == nil ? (quantity ?? 1) : 1
                grams = value * factor * count
            }
            name = tidyName(name.replacingCharacters(in: match.range, with: ""))
        }

        var line = IngredientLine(raw: raw, name: name, quantity: quantity, unit: quantity == nil ? nil : unit, guessed: guessed)
        if let grams, line.unit == "piece" || line.unit == nil { line.gramsOverride = grams }
        return line
    }

    /// Remove bullets, emojis and list markers.
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.unicodeScalars.first,
              first.properties.isEmojiPresentation || "-•*·▪︎◦–—>✓✔︎☐□".unicodeScalars.contains(first) || first.properties.generalCategory == .otherSymbol {
            text = String(text.unicodeScalars.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        return text.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func tidyName(_ text: String) -> String {
        var name = text.trimmingCharacters(in: .whitespaces)
        for prefix in ["de ", "d'", "d’", "of ", "du ", "des "] where name.lowercased().hasPrefix(prefix) {
            name = String(name.dropFirst(prefix.count))
            break
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:-"))
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    private static func unitKey(_ label: String) -> String? {
        let lower = label.lowercased()
        return unitLabels.first { $0.label == lower }?.key
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }

    /// Does this line look like an ingredient (rather than a sentence or a title)?
    static func looksLikeIngredient(_ raw: String) -> Bool {
        let text = clean(raw)
        guard !text.isEmpty, text.count < 90 else { return false }
        if text.firstMatch(of: /^([0-9]+(?:[.,][0-9]+)?|[½¼¾⅓⅔])\s*(\/\s*[0-9]+\s*)?[^[0-9].):]/) != nil {
            return text.split(separator: " ").count <= 12
        }
        let line = parse(text)
        return line.quantity != nil || (FoodTable.match(text) != nil && text.split(separator: " ").count <= 5)
    }
}
