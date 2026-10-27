import SwiftUI

/// "Check the import": title, servings, ingredient lines and steps, editable as text.
/// Lines read from a caption are highlighted until saved.
struct RecipeEditView: View {
    @Bindable var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var servings = 2
    @State private var minutes = ""
    @State private var lines: [IngredientLine] = []
    @State private var steps: [RecipeStep] = []
    @State private var caption = ""
    @State private var structuring = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical)
                    Stepper("^[\(servings) serving](inflect: true)", value: $servings, in: 1...24)
                    HStack {
                        Text("Total time")
                        Spacer()
                        TextField("min", text: $minutes).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80)
                        Text("min").foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach($lines) { $line in
                        HStack {
                            if line.guessed {
                                Image(systemName: "sparkles").foregroundStyle(Theme.carbs).font(.caption)
                            }
                            TextField("200 g flour", text: $line.raw, axis: .vertical)
                        }
                        .listRowBackground(line.guessed ? Theme.carbs.opacity(0.08) : nil)
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    .onMove { lines.move(fromOffsets: $0, toOffset: $1) }
                    Button { lines.append(IngredientLine(raw: "", name: "")) } label: { Label("Add an ingredient", systemImage: "plus") }
                } header: {
                    Text("Ingredients")
                } footer: {
                    if lines.contains(where: \.guessed) {
                        Text("Highlighted lines were read automatically. Write them like \"200 g flour\" or \"2 tbsp olive oil\".")
                    }
                }

                Section("Steps") {
                    ForEach($steps) { $step in
                        TextField("Step", text: $step.text, axis: .vertical)
                    }
                    .onDelete { steps.remove(atOffsets: $0) }
                    .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
                    Button { steps.append(RecipeStep(text: "")) } label: { Label("Add a step", systemImage: "plus") }
                }

                Section {
                    TextEditor(text: $caption).frame(minHeight: 120)
                    Button {
                        structuring = true
                        Task {
                            let result = await RecipeStructurer.structure(caption)
                            if !result.ingredients.isEmpty { lines = result.ingredients }
                            if !result.steps.isEmpty { steps = result.steps }
                            if let n = result.servings { servings = n }
                            structuring = false
                        }
                    } label: {
                        HStack {
                            Label("Read the recipe from this text", systemImage: "sparkles")
                            if structuring { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || structuring)
                } header: {
                    Text("Caption")
                } footer: {
                    Text("Paste the caption or description here if the import missed it.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Check the recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        title = recipe.title
        servings = recipe.servings
        minutes = recipe.minutes.map(String.init) ?? ""
        lines = recipe.ingredients
        steps = recipe.steps
        caption = recipe.rawText ?? ""
    }

    private func save() {
        let old = Dictionary(recipe.ingredients.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        recipe.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.servings = servings
        if !recipe.inShoppingList { recipe.shoppingServings = servings }
        recipe.minutes = Int(minutes)
        recipe.ingredients = lines.compactMap { line in
            let raw = line.raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            // Re-read edited lines; keep the nutrition match when the line didn't change.
            if let previous = old[line.id], previous.raw == raw {
                var kept = previous
                kept.guessed = false
                return kept
            }
            var parsed = IngredientParser.parse(raw)
            parsed.id = line.id
            return parsed
        }
        recipe.steps = steps.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        recipe.rawText = caption.isEmpty ? nil : caption
        recipe.needsReview = false
        dismiss()
    }
}
