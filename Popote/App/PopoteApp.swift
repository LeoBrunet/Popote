import SwiftData
import SwiftUI

@main
struct PopoteApp: App {
    @State private var imports = ImportCenter()
    @State private var health = HealthService()
    @State private var claude = ClaudeSync()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(imports)
                .environment(health)
                .environment(claude)
                .tint(Theme.accent)
        }
        .modelContainer(for: [Recipe.self, JournalEntry.self, PantryItem.self, ShoppingCheck.self, MealDraft.self])
    }
}

enum Tab: Hashable { case recipes, groceries, journal, pantry }

struct RootView: View {
    @Environment(ImportCenter.self) private var imports
    @Environment(HealthService.self) private var health
    @Environment(ClaudeSync.self) private var claude
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = Tab.recipes
    @State private var showAdd = false
    @State private var openRecipe: UUID?

    var body: some View {
        ZStack {
            switch tab {
            case .recipes: LibraryView(openRecipe: $openRecipe)
            case .groceries: GroceryView()
            case .journal: JournalView()
            case .pantry: PantryView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(selected: $tab) { showAdd = true }
        }
        // The + is for logging food; recipes are created from the Recettes screen.
        .sheet(isPresented: $showAdd) {
            LogMealSheet()
                .presentationDetents([.large])
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .background {
                // Leaving for Claude (or anywhere): share what was just logged so Claude can read it.
                let task = UIApplication.shared.beginBackgroundTask()
                Task {
                    await claude.shareContext(context: context, health: health)
                    UIApplication.shared.endBackgroundTask(task)
                }
                return
            }
            guard phase == .active else { return }
            imports.processInbox(context: context)
            Task {
                await health.refresh()
                MaintenanceLearner.update(context: context, health: health)   // weekly: weight trend vs intake
                await claude.sync(context: context, health: health)   // share pantry/targets, bring in Claude's recipes and meals
            }
        }
        .onOpenURL { url in
            // popote://import?url=https://…
            if let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value,
               let target = URL(string: link) {
                tab = .recipes
                imports.start(url: target, context: context)
            } else {
                imports.processInbox(context: context)
            }
        }
    }
}

/// Bottom tab bar with the central add button, as in the mockups.
struct TabBar: View {
    @Binding var selected: Tab
    let add: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            item(.recipes, "Recipes", "book")
            item(.groceries, "Groceries", "cart")
            Button(action: add) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.onAccent)
                    .frame(width: 50, height: 50)
                    .background(Theme.accent, in: Circle())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 8, y: 4)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("Add")
            item(.journal, "Journal", "chart.pie")
            item(.pantry, "Pantry", "cabinet")
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(.bar)
    }

    private func item(_ tab: Tab, _ title: LocalizedStringKey, _ icon: String) -> some View {
        Button { selected = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: icon + (tab == selected ? ".fill" : "")).font(.system(size: 18))
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(tab == selected ? Theme.accent : .secondary)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
