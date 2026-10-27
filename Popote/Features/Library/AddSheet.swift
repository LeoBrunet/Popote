import SwiftData
import SwiftUI

/// The + button: import a copied link, type one, or write a recipe by hand.
struct AddSheet: View {
    let opened: (UUID) -> Void
    @Environment(ImportCenter.self) private var imports
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @FocusState private var linkFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.Spacing.m) {
                PasteButton(payloadType: URL.self) { urls in
                    guard let url = urls.first else { return }
                    Task { @MainActor in importLink(url) }
                }
                .buttonBorderShape(.capsule)
                .tint(Theme.accent)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text("Or paste a link").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("https://www.instagram.com/reel/…", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($linkFocused)
                            .submitLabel(.go)
                            .onSubmit(importTyped)
                        Button("Import", action: importTyped).disabled(URL(string: link)?.host() == nil)
                    }
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    let recipe = Recipe(title: String(localized: "New recipe"), source: .manual)
                    recipe.needsReview = true
                    context.insert(recipe)
                    dismiss()
                    opened(recipe.id)
                } label: {
                    Label("Write a recipe", systemImage: "square.and.pencil")
                }
                .buttonStyle(PrimaryButtonStyle(secondary: true))

                Label("Tip: in Instagram, YouTube or TikTok, tap Share › Popote. The recipe is imported in the background.",
                      systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .background(Theme.background)
            .navigationTitle("Add a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func importTyped() {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.hasPrefix("http") ? trimmed : "https://" + trimmed), url.host() != nil else { return }
        importLink(url)
    }

    private func importLink(_ url: URL) {
        imports.start(url: url, context: context)
        dismiss()
    }
}
