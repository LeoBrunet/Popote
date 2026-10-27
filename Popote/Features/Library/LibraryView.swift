import SwiftData
import SwiftUI

struct LibraryView: View {
    @Binding var openRecipe: UUID?
    @Environment(ImportCenter.self) private var imports
    @Environment(ClaudeSync.self) private var claude
    @Environment(\.modelContext) private var context
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]
    @State private var search = ""
    @State private var filter: RecipeSource?
    @State private var path = NavigationPath()
    @State private var showSettings = false
    @State private var showImport = false
    @State private var showClaude = false

    private var filtered: [Recipe] {
        recipes.filter { recipe in
            (filter == nil || recipe.source == filter)
                && (search.isEmpty || recipe.title.localizedCaseInsensitiveContains(search)
                    || recipe.ingredients.contains { $0.name.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    ScreenHeader(title: "Recipes", logo: true) {
                        Button { showSettings = true } label: { RoundIcon(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                        Menu {
                            Button { showImport = true } label: { Label("Import a link", systemImage: "link") }
                            Button { showClaude = true } label: { Label("Create with Claude", systemImage: "sparkle") }
                            Button { writeRecipe() } label: { Label("Write a recipe", systemImage: "square.and.pencil") }
                        } label: {
                            RoundIcon(systemName: "plus")
                        }
                        .accessibilityLabel("New recipe")
                    }
                    searchField
                    ImportBanner { id in path.append(id) }
                    ForEach(claude.newRecipes, id: \.id) { item in
                        HStack(spacing: DS.Spacing.s) {
                            ClaudeMark(size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("New recipe from Claude").font(.subheadline.weight(.semibold))
                                Text(item.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Button("Open") {
                                path.append(item.id)
                                claude.newRecipes.removeAll { $0.id == item.id }
                            }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            Button { claude.newRecipes.removeAll { $0.id == item.id } } label: {
                                Image(systemName: "xmark").foregroundStyle(.secondary)
                            }
                            .accessibilityLabel("Dismiss")
                        }
                        .card(padding: DS.Spacing.s)
                    }
                    if recipes.isEmpty {
                        EmptyLibrary()
                    } else {
                        filters
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: DS.Spacing.s), GridItem(.flexible(), spacing: DS.Spacing.s)],
                                  spacing: DS.Spacing.s) {
                            ForEach(filtered) { recipe in
                                NavigationLink(value: recipe.id) { RecipeCard(recipe: recipe) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
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
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showImport) {
                AddSheet { id in path.append(id) }.presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showClaude) { ClaudeRecipeView() }
        }
        .onChange(of: openRecipe, initial: true) { _, id in
            guard let id else { return }
            path.append(id)
            openRecipe = nil
        }
    }

    private func writeRecipe() {
        let recipe = Recipe(title: String(localized: "New recipe"), source: .manual)
        recipe.needsReview = true
        context.insert(recipe)
        path.append(recipe.id)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search a recipe or an ingredient", text: $search)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.card, in: Capsule())
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.Spacing.xs) {
                Button { filter = nil } label: { Chip(text: "All", selected: filter == nil) }
                ForEach([RecipeSource.instagram, .youtube, .tiktok, .web], id: \.self) { source in
                    if recipes.contains(where: { $0.source == source }) {
                        Button { filter = filter == source ? nil : source } label: {
                            Chip(text: LocalizedStringKey(source.name), selected: filter == source, icon: source.icon)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct RecipeCard: View {
    let recipe: Recipe

    var body: some View {
        let nutrition = NutritionEngine.evaluate(recipe)
        VStack(alignment: .leading, spacing: 0) {
            RecipePhoto(recipe: recipe)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) { SourceBadge(source: recipe.source, compact: true).padding(8) }
                .overlay(alignment: .topTrailing) {
                    if recipe.needsReview {
                        // Read from a caption: quantities may need a look ("Check the import" in the recipe).
                        Label("To check", systemImage: "sparkles")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(Theme.carbs, in: Capsule())
                            .padding(6)
                    } else if recipe.inShoppingList {
                        Image(systemName: "cart.circle.fill").foregroundStyle(.white, Theme.herb).font(.title3).padding(6)
                    }
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    if nutrition.perServing.kcal > 0 {
                        Text("\(Int(nutrition.perServing.kcal)) kcal")
                    }
                    if let minutes = recipe.minutes {
                        Label("\(minutes) min", systemImage: "clock").labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(10)
        }
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Imports in progress / finished / failed, shown at the top of the library.
private struct ImportBanner: View {
    let open: (UUID) -> Void
    @Environment(ImportCenter.self) private var imports
    @Environment(ClaudeSync.self) private var claude

    var body: some View {
        ForEach(imports.jobs) { job in
            HStack(spacing: DS.Spacing.s) {
                switch job.state {
                case .running:
                    ProgressView().frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Importing…").font(.subheadline.weight(.semibold))
                        Text(job.url.host() ?? job.url.absoluteString).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                case .done(let id):
                    Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(Theme.herb)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Recipe ready").font(.subheadline.weight(.semibold))
                        Text(job.title ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button("Open") { open(id); imports.dismiss(job.id) }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                case .failed(let message):
                    Image(systemName: "exclamationmark.triangle.fill").font(.title2).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Import failed").font(.subheadline.weight(.semibold))
                        Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    Button { imports.dismiss(job.id) } label: { Image(systemName: "xmark").foregroundStyle(.secondary) }
                }
            }
            .card(padding: DS.Spacing.s)
        }
    }
}

private struct EmptyLibrary: View {
    var body: some View {
        VStack(spacing: DS.Spacing.m) {
            AppMark(size: 72).padding(.top, DS.Spacing.l)
            Text("Your recipes will live here").font(Theme.titleFont).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: DS.Spacing.s) {
                Label("In Instagram, YouTube, TikTok or Safari, tap Share, then Popote.", systemImage: "square.and.arrow.up")
                Label("Or tap + at the top to paste a link, create with Claude or write one.", systemImage: "plus.circle")
                Label("Popote finds the ingredients, the steps and the macros.", systemImage: "sparkles")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .card()
        }
        .frame(maxWidth: .infinity)
    }
}
