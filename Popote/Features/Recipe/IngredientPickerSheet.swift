import SwiftData
import SwiftUI

/// Add an ingredient to a recipe from a product or a food instead of typing it:
/// products used before (journal and recipes), a barcode scan, or a search (foods and Open Food Facts).
struct IngredientPickerSheet: View {
    let add: (IngredientLine) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var mode = Mode.recent
    @State private var query = ""
    @State private var products: [ProductSnapshot] = []
    @State private var searching = false
    @State private var message: String?
    @State private var chosen: Choice?

    enum Mode: Hashable { case recent, scan, search }

    /// A product or a food, waiting for its weight.
    struct Choice: Identifiable, Hashable {
        var id: String { product?.code ?? foodID ?? name }
        let name: String
        var detail = ""
        var product: ProductSnapshot?
        var foodID: String?
        let per100g: Nutrition
        var servingGrams: Double?
    }

    /// Products already used in the journal or in recipes, most recent first, once each.
    private var recentProducts: [ProductSnapshot] {
        var seen = Set<String>()
        let lines = entries.flatMap(\.lines) + recipes.flatMap(\.ingredients)
        return lines.compactMap(\.product).filter { seen.insert($0.code).inserted }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Source", selection: $mode) {
                    Text("My products").tag(Mode.recent)
                    Text("Scan").tag(Mode.scan)
                    Text("Search").tag(Mode.search)
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .recent: recentList
                case .scan: scanner
                case .search: searchList
                }
            }
            .background(Theme.background)
            .navigationTitle("Add an ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .navigationDestination(item: $chosen) { choice in
                IngredientWeightView(choice: choice) { line in
                    add(line)
                    dismiss()
                }
            }
            .onAppear { if recentProducts.isEmpty { mode = .search } }
        }
    }

    private var recentList: some View {
        List(recentProducts, id: \.code) { product in
            Button { chosen = choice(product) } label: { row(product.name, detail: product.brand ?? "", kcal: product.kcal) }
        }
        .overlay {
            if recentProducts.isEmpty {
                ContentUnavailableView("No products yet", systemImage: "barcode",
                                       description: Text("Products you scan or pick show up here."))
            }
        }
    }

    private var scanner: some View {
        VStack {
            BarcodeScanner { code in
                Task {
                    if let product = try? await OpenFoodFacts.product(barcode: code) {
                        chosen = choice(product)
                    } else {
                        message = String(localized: "Product \(code) isn't in Open Food Facts.")
                    }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accent).padding() }
        }
    }

    private var searchList: some View {
        List {
            Section("Foods") {
                ForEach(FoodTable.search(query).filter { !$0.staple }.prefix(query.isEmpty ? 10 : 30)) { food in
                    Button {
                        chosen = Choice(name: food.name, detail: food.aisle.name, foodID: food.id, per100g: food.per100g, servingGrams: food.pieceGrams)
                    } label: { row(food.name, detail: food.aisle.name, kcal: food.per100g.kcal) }
                }
            }
            Section {
                if searching { ProgressView() }
                ForEach(products, id: \.code) { product in
                    Button { chosen = choice(product) } label: { row(product.name, detail: product.brand ?? "", kcal: product.kcal) }
                }
                if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
            } header: {
                HStack {
                    Text("Products (Open Food Facts)")
                    Spacer()
                    Button("Search") { searchProducts() }.font(.caption.weight(.semibold)).disabled(query.isEmpty)
                }
            }
        }
        .searchable(text: $query, prompt: "Search a food or a product")
        .onSubmit(of: .search) { searchProducts() }
    }

    private func choice(_ product: ProductSnapshot) -> Choice {
        Choice(name: product.name, detail: product.brand ?? "", product: product,
               per100g: Nutrition(kcal: product.kcal, protein: product.protein, carbs: product.carbs, fat: product.fat),
               servingGrams: product.servingGrams)
    }

    private func row(_ name: String, detail: String, kcal: Double) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(Color.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(Int(kcal)) kcal/100 g").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func searchProducts() {
        guard !query.isEmpty else { return }
        searching = true
        message = nil
        Task {
            do { products = try await OpenFoodFacts.search(query) } catch { message = error.localizedDescription }
            if products.isEmpty && message == nil { message = String(localized: "No product found.") }
            searching = false
        }
    }
}

/// How much of the chosen product or food goes into the recipe.
private struct IngredientWeightView: View {
    let choice: IngredientPickerSheet.Choice
    let add: (IngredientLine) -> Void
    @State private var grams = ""

    private var value: Double { Double(grams.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Quantity")
                    Spacer()
                    TextField("100", text: $grams).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                    Text("g").foregroundStyle(.secondary)
                }
                if let serving = choice.servingGrams {
                    Button("1 serving (\(Int(serving)) g)") { grams = "\(Int(serving))" }
                }
            } footer: {
                if !choice.detail.isEmpty { Text(choice.detail) }
            }
            Section { MacroSummary(nutrition: choice.per100g * (value / 100), caption: "kcal") }
        }
        .navigationTitle(choice.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    add(IngredientLine(raw: "\(Units.formatNumber(value)) g \(choice.name)", name: choice.name, quantity: value, unit: "g",
                                       foodID: choice.foodID, product: choice.product, gramsOverride: value))
                }
                .bold()
                .disabled(value <= 0)
            }
        }
        .onAppear { grams = choice.servingGrams.map { "\(Int($0))" } ?? "100" }
    }
}
