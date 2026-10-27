import SwiftData
import SwiftUI

struct GroceryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Recipe> { $0.inShoppingList }, sort: \Recipe.title) private var recipes: [Recipe]
    @Query private var pantry: [PantryItem]
    @Query private var checks: [ShoppingCheck]
    @AppStorage("bringListName") private var bringListName = ""
    @State private var showBring = false
    @State private var showConnect = false
    @State private var showPantry = false

    var body: some View {
        let list = ShoppingList.build(recipes: recipes, pantryKeys: Set(pantry.map(\.key)))
        let checked = Set(checks.map(\.key))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    ScreenHeader(title: "Groceries") {
                        if !list.toBuy.isEmpty {
                            ShareLink(item: ShoppingList.text(list.toBuy.filter { !checked.contains($0.key) })) {
                                RoundIcon(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                    if recipes.isEmpty {
                        empty
                    } else {
                        recipeStrip
                        bringCard(count: list.toBuy.filter { !checked.contains($0.key) }.count)
                        ForEach(Aisle.allCases, id: \.self) { aisle in
                            let items = list.toBuy.filter { $0.aisle == aisle }
                            if !items.isEmpty { aisleSection(aisle, items, checked: checked) }
                        }
                        if !list.inPantry.isEmpty { pantrySection(list.inPantry) }
                    }
                }
                .padding(.horizontal, DS.Spacing.m)
                .padding(.bottom, DS.Spacing.l)
            }
            .background(Theme.background)
            .statusBarBackdrop()
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showBring) { BringSyncView(items: list.toBuy.filter { !checked.contains($0.key) }) }
            .sheet(isPresented: $showConnect) { BringConnectView() }
        }
    }

    private var empty: some View {
        VStack(spacing: DS.Spacing.s) {
            Image(systemName: "cart").font(.system(size: 44)).foregroundStyle(Theme.accent)
            Text("Your list is empty").font(Theme.titleFont)
            Text("Open a recipe and tap \"Add to groceries\". Quantities from several recipes are added up and sorted by aisle.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .card(padding: DS.Spacing.l)
    }

    private var recipeStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.s) {
                ForEach(recipes) { recipe in
                    VStack(alignment: .leading, spacing: 6) {
                        RecipePhoto(recipe: recipe, symbolSize: 20)
                            .frame(width: 150, height: 70)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button { recipe.inShoppingList = false } label: {
                                    Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.white, .black.opacity(0.4))
                                }
                                .padding(4)
                                .accessibilityLabel("Remove from the list")
                            }
                        Text(recipe.title).font(.caption.weight(.semibold)).lineLimit(1).frame(width: 150, alignment: .leading)
                        HStack(spacing: 8) {
                            Button { recipe.shoppingServings = max(1, recipe.shoppingServings - 1) } label: { Image(systemName: "minus.circle") }
                            Text("^[\(recipe.shoppingServings) serving](inflect: true)").font(.caption.monospacedDigit())
                            Button { recipe.shoppingServings += 1 } label: { Image(systemName: "plus.circle") }
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .padding(8)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private func bringCard(count: Int) -> some View {
        let connected = Keychain.get("bring.email") != nil && !bringListName.isEmpty
        return Button { connected ? (showBring = true) : (showConnect = true) } label: {
            HStack(spacing: DS.Spacing.s) {
                Text("B!")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(Color(red: 0.93, green: 0.30, blue: 0.24), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text(connected ? "Sync with Bring!" : "Connect Bring!").font(.subheadline.weight(.semibold))
                    Text(connected
                         ? "\(count) items · merged with what's already on \"\(bringListName)\""
                         : "Send this list to Bring!, merged with what's already on it")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: DS.Spacing.s)
        }
        .buttonStyle(.plain)
    }

    private func aisleSection(_ aisle: Aisle, _ items: [ShoppingItem], checked: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Label(aisle.name, systemImage: aisle.icon).font(.headline)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    let isChecked = checked.contains(item.key)
                    Button { toggle(item.key, checked: isChecked) } label: {
                        HStack(spacing: DS.Spacing.s) {
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(isChecked ? Theme.herb : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name).strikethrough(isChecked).foregroundStyle(isChecked ? .secondary : .primary)
                                if item.recipes.count > 1 {
                                    Text(item.recipes.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(item.quantity).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { addToPantry(item) } label: { Label("I already have it", systemImage: "cabinet") }
                    }
                    if item.id != items.last?.id { Divider() }
                }
            }
            .card(padding: DS.Spacing.s)
        }
    }

    private func pantrySection(_ items: [ShoppingItem]) -> some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Button { withAnimation { showPantry.toggle() } } label: {
                HStack {
                    Label("Already in your pantry (\(items.count))", systemImage: "cabinet").font(.headline)
                    Spacer()
                    Image(systemName: showPantry ? "chevron.up" : "chevron.down").foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if showPantry {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(items) { item in
                        HStack {
                            Text(item.name)
                            Spacer()
                            Text(item.quantity).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .foregroundStyle(.secondary)
                .card(padding: DS.Spacing.s)
            }
        }
    }

    private func toggle(_ key: String, checked: Bool) {
        if checked {
            for check in checks where check.key == key { context.delete(check) }
        } else {
            context.insert(ShoppingCheck(key: key))
        }
    }

    private func addToPantry(_ item: ShoppingItem) {
        context.insert(PantryItem(name: item.name, key: item.key))
    }
}
