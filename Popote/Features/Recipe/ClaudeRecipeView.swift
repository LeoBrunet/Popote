import SwiftData
import SwiftUI

/// "Create with Claude": write the request here, Claude creates the recipe in the Claude app
/// (your own plan, via the Popote connector) and saves it to Popote with save_recipe.
struct ClaudeRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(ClaudeSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query private var pantry: [PantryItem]
    @State private var request = ""
    @State private var usePantry = true
    @State private var useTargets = true
    @State private var sending = false
    @State private var showSetup = false
    @FocusState private var focused: Bool

    static let orange = Color(red: 0.85, green: 0.47, blue: 0.34)
    private let ideas = ["< 20 min", "Vegetarian", "Batch 4 servings", "No oven", "Before a workout"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    if !sync.claudeConnected { setupBanner }
                    HStack(spacing: DS.Spacing.s) {
                        ClaudeMark(size: 36)
                        Text("What would you like?").font(Theme.titleFont)
                    }
                    TextField("A quick dish with the chicken and sweet potatoes I have left, high in protein", text: $request, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
                        .card()
                    Text("Take into account").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(spacing: 0) {
                        Toggle(isOn: $usePantry) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("My pantry")
                                    Text("^[\(pantry.count) ingredient](inflect: true)").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "cabinet").foregroundStyle(Theme.accent) }
                        }
                        Divider().padding(.vertical, 6)
                        Toggle(isOn: $useTargets) {
                            Label {
                                VStack(alignment: .leading) {
                                    Text("Today's targets")
                                    Text("Calories and macros left for today").font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "chart.pie").foregroundStyle(Theme.accent) }
                        }
                    }
                    .tint(Theme.accent)
                    .card(padding: DS.Spacing.s)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(ideas, id: \.self) { idea in
                                Button { append(idea) } label: { Chip(text: LocalizedStringKey(idea)) }.buttonStyle(.plain)
                            }
                        }
                    }
                    VStack(spacing: 6) {
                        Button { Task { await openClaude() } } label: {
                            if sending { ProgressView().tint(.white) } else { Label("Continue in Claude", systemImage: "arrow.up.forward.app") }
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(request.trimmingCharacters(in: .whitespaces).isEmpty || sending)
                        Text("Claude shows you the recipe, you adjust it together, and it lands in your recipes.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .padding(DS.Spacing.m)
            }
            .background(Theme.background)
            .navigationTitle("Create with Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showSetup) { ConnectClaudeView() }
        }
    }

    private var setupBanner: some View {
        Button { showSetup = true } label: {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: "link.badge.plus").foregroundStyle(Self.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect Popote to Claude").font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text("One time: add the Popote connector in the Claude app.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .card(padding: DS.Spacing.s)
        }
        .buttonStyle(.plain)
    }

    private func append(_ idea: String) {
        let localized = String(localized: String.LocalizationValue(idea))
        request = request.isEmpty ? localized : request + ", " + localized.lowercased()
    }

    /// Shares the latest pantry and targets with the server, then hands the request to Claude.
    private func openClaude() async {
        focused = false
        sending = true
        await sync.sync(context: context, health: health)
        sending = false
        ClaudeLink.open(ClaudeLink.createRecipe(request.trimmingCharacters(in: .whitespacesAndNewlines), usePantry: usePantry, useTargets: useTargets))
        dismiss()
    }
}

/// Claude's mark: a sparkle on an orange disc.
struct ClaudeMark: View {
    var size: CGFloat = 28
    var body: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(ClaudeRecipeView.orange, in: Circle())
            .accessibilityHidden(true)
    }
}
