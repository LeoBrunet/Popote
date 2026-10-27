import SwiftData
import SwiftUI

/// What's at home: removed from the shopping list, and used to suggest what to cook tonight.
struct PantryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PantryItem.name) private var items: [PantryItem]
    @Query private var recipes: [Recipe]
    @State private var newItem = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    ScreenHeader(title: "Pantry") { EmptyView() }
                    addField
                    if !cookable.isEmpty { tonight }
                    list
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(Theme.background)
            .statusBarBackdrop()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: UUID.self) { id in
                if let recipe = recipes.first(where: { $0.id == id }) { RecipeDetailView(recipe: recipe) }
            }
        }
    }

    private var addField: some View {
        HStack {
            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
            TextField("Add what you have (rice, eggs, feta…)", text: $newItem)
                .submitLabel(.done)
                .onSubmit(add)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card, in: Capsule())
    }

    private struct Cookable {
        let recipe: Recipe
        let have: Int
        let total: Int
        var share: Double { Double(have) / Double(total) }
    }

    /// Recipes ranked by the share of their ingredients already at home.
    private var cookable: [Cookable] {
        let keys = Set(items.map(\.key))
        guard !keys.isEmpty else { return [] }
        var result: [Cookable] = []
        for recipe in recipes {
            let lines = recipe.ingredients.filter { NutritionEngine.food(for: $0)?.staple != true }
            guard !lines.isEmpty else { continue }
            let have = lines.filter { line in
                let key = NutritionEngine.food(for: line)?.id ?? TextKey.key(line.name)
                return keys.contains(key)
            }.count
            if have * 2 >= lines.count { result.append(Cookable(recipe: recipe, have: have, total: lines.count)) }
        }
        return Array(result.sorted { $0.share > $1.share }.prefix(5))
    }

    private var tonight: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionTitle(text: "Tonight you can cook")
            ForEach(cookable, id: \.recipe.id) { item in
                NavigationLink(value: item.recipe.id) {
                    HStack(spacing: DS.Spacing.s) {
                        RecipePhoto(recipe: item.recipe, symbolSize: 16)
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.recipe.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                            Group {
                                if item.have == item.total {
                                    Text("You have everything").foregroundStyle(Theme.herb)
                                } else {
                                    Text("^[\(item.total - item.have) ingredient](inflect: true) missing").foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    .card(padding: DS.Spacing.s)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            SectionTitle(text: "At home", trailing: items.isEmpty ? nil : "\(items.count)")
            if items.isEmpty {
                Text("Items you add here are left off the shopping list. Long-press an item in Groceries to move it here.")
                    .font(.subheadline).foregroundStyle(.secondary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Button { context.delete(item) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }
                                .accessibilityLabel("Remove")
                        }
                        .padding(.vertical, 9)
                        if item.id != items.last?.id { Divider() }
                    }
                }
                .card(padding: DS.Spacing.s)
            }
        }
    }

    private func add() {
        let name = newItem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let food = FoodTable.match(name)
        let key = food?.id ?? TextKey.key(name)
        if !items.contains(where: { $0.key == key }) {
            context.insert(PantryItem(name: food?.name ?? name.prefix(1).uppercased() + name.dropFirst(), key: key))
        }
        newItem = ""
    }
}
