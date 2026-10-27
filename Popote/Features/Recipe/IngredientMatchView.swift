import SwiftUI

/// Pick the nutrition source of one ingredient: a generic food, a product (search or barcode), or not counted.
/// With `substitute`, picking a food or product replaces the ingredient (new name, same weight): used in the journal.
struct IngredientMatchView: View {
    @Binding var lines: [IngredientLine]
    let line: IngredientLine
    var substitute = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var grams = ""
    @State private var products: [ProductSnapshot] = []
    @State private var searching = false
    @State private var scanning = false
    @State private var error: String?

    var body: some View {
        let live = lines.first { $0.id == line.id } ?? line
        let current = NutritionEngine.evaluate(live)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(substitute ? live.name : line.raw).font(.headline)
                        HStack {
                            MatchBadge(kind: current.kind)
                            if let g = current.grams { Text("≈ \(Int(g)) g").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            Text("\(Int(current.nutrition.kcal)) kcal").font(.subheadline.monospacedDigit())
                        }
                    }
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField(current.grams.map { "\(Int($0))" } ?? "g", text: $grams)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("g").foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Set the weight when the quantity can't be converted (\"1 bunch\", \"a handful\").")
                }

                Section {
                    Button { scanning = true } label: { Label("Scan a barcode", systemImage: "barcode.viewfinder") }
                    Button {
                        update { $0.ignored = true; $0.foodID = nil; $0.product = nil }
                    } label: { Label("Don't count it", systemImage: "minus.circle") }
                }

                Section("Foods") {
                    ForEach(FoodTable.search(query).prefix(query.isEmpty ? 8 : 30)) { food in
                        Button {
                            update { $0.foodID = food.id; $0.product = nil; $0.ignored = false; rename(&$0, to: food.name) }
                            if substitute { dismiss() }
                        } label: {
                            row(food.name, detail: food.aisle.name, kcal: food.per100g.kcal, selected: live.foodID == food.id && !live.ignored)
                        }
                    }
                }

                Section {
                    if searching { ProgressView() }
                    ForEach(products, id: \.code) { product in
                        Button { choose(product) } label: {
                            row(product.name, detail: product.brand ?? "", kcal: product.kcal, selected: live.product?.code == product.code)
                        }
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                } header: {
                    HStack {
                        Text("Products (Open Food Facts)")
                        Spacer()
                        Button("Search") { searchProducts() }.font(.caption.weight(.semibold)).disabled(query.isEmpty)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search a food or a product")
            .onSubmit(of: .search) { searchProducts() }
            .navigationTitle(line.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let value = Double(grams.replacingOccurrences(of: ",", with: ".")) { update { $0.gramsOverride = value } }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    BarcodeScanner { code in
                        scanning = false
                        Task {
                            if let product = try? await OpenFoodFacts.product(barcode: code) {
                                choose(product)
                            } else {
                                error = String(localized: "Product \(code) isn't in Open Food Facts.")
                            }
                        }
                    }
                    .ignoresSafeArea()
                    .navigationTitle("Scan").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { scanning = false } } }
                }
            }
            .onAppear { query = !substitute && TextKey.normalize(line.name).count < 30 ? line.name : "" }
        }
    }

    private func row(_ name: String, detail: String, kcal: Double, selected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).foregroundStyle(Color.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text("\(Int(kcal)) kcal/100 g").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if selected { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
        }
    }

    private func searchProducts() {
        guard !query.isEmpty else { return }
        searching = true
        error = nil
        Task {
            do { products = try await OpenFoodFacts.search(query) } catch { self.error = error.localizedDescription }
            if products.isEmpty && error == nil { error = String(localized: "No product found.") }
            searching = false
        }
    }

    private func choose(_ product: ProductSnapshot) {
        update { $0.product = product; $0.foodID = nil; $0.ignored = false; rename(&$0, to: product.name) }
        dismiss()
    }

    /// Substitution keeps the weight that was eaten and drops what belonged to the old ingredient.
    private func rename(_ line: inout IngredientLine, to name: String) {
        guard substitute, name != line.name else { return }
        let grams = NutritionEngine.evaluate(self.line).grams
        line.name = name
        line.estimate = nil
        if let grams {
            line.quantity = grams
            line.unit = "g"
            line.gramsOverride = grams
        }
        line.raw = "\(Units.format(line.quantity, unit: line.unit)) \(name)".trimmingCharacters(in: .whitespaces)
    }

    private func update(_ change: (inout IngredientLine) -> Void) {
        guard let i = lines.firstIndex(where: { $0.id == line.id }) else { return }
        change(&lines[i])
    }
}
