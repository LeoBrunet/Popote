import SwiftData
import SwiftUI

/// Edit a logged meal. Saving rewrites it in Apple Health (old sample deleted, new one saved).
struct EditEntrySheet: View {
    let entry: JournalEntry
    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var meal = Meal.lunch
    @State private var date = Date()
    @State private var amount = 1.0
    @State private var grams = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var shown = Nutrition.zero      // values behind the text fields, kept exact
    @State private var saving = false
    @State private var confirmDelete = false

    private var isGrams: Bool { entry.amountUnit == "g" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("Meal", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.name).tag($0) }
                    }
                    DatePicker("When", selection: $date)
                }

                if entry.amount != nil {
                    Section {
                        if isGrams {
                            HStack {
                                Text("Quantity")
                                Spacer()
                                TextField("100", text: $grams)
                                    .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                                    .onChange(of: grams) { _, value in
                                        if let g = number(value), g > 0 { rescale(to: g) }
                                    }
                                Text("g").foregroundStyle(.secondary)
                            }
                        } else {
                            Stepper(value: $amount, in: 0.5...12, step: 0.5) { Text(Units.servings(amount)) }
                                .onChange(of: amount) { _, value in rescale(to: value) }
                        }
                    } footer: {
                        Text("Changing the quantity updates the calories and macros.")
                    }
                }

                Section("Nutrition") {
                    field("Calories", $kcal, unit: "kcal")
                    field("Protein", $protein, unit: "g")
                    field("Carbs", $carbs, unit: "g")
                    field("Fat", $fat, unit: "g")
                }

                Section {
                    Button("Delete", role: .destructive) { confirmDelete = true }
                } footer: {
                    if health.connected {
                        Label("Changes are saved to Apple Health too.", systemImage: "heart.fill")
                    }
                }
            }
            .navigationTitle("Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if saving { ProgressView() } else { Button("Save", action: save).bold() }
                }
            }
            .confirmationDialog("Delete this meal?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let uuid = entry.healthUUID { Task { await health.delete(healthUUID: uuid) } }
                    context.delete(entry)
                    dismiss()
                }
            }
            .onAppear(perform: load)
        }
    }

    private func field(_ label: LocalizedStringKey, _ value: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: value).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
        }
    }

    private func load() {
        title = entry.title
        meal = entry.meal
        date = entry.date
        amount = entry.amount ?? 1
        grams = entry.amount.map { "\(Int($0.rounded()))" } ?? ""
        show(entry.nutrition)
    }

    private func show(_ n: Nutrition) {
        shown = n
        kcal = "\(Int(n.kcal.rounded()))"
        protein = n.protein.formatted(.number.precision(.fractionLength(0...1)))
        carbs = n.carbs.formatted(.number.precision(.fractionLength(0...1)))
        fat = n.fat.formatted(.number.precision(.fractionLength(0...1)))
    }

    /// Scale the logged nutrition from the original amount to the new one.
    private func rescale(to value: Double) {
        guard let original = entry.amount, original > 0 else { return }
        show(entry.nutrition * (value / original))
    }

    private func number(_ text: String) -> Double? {
        let parsed = (try? Double(text, format: .number)) ?? Double(text.replacingOccurrences(of: ",", with: "."))
        return parsed
    }

    private func save() {
        entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry.title : title
        entry.meal = meal
        entry.date = date
        if entry.amount != nil {
            if isGrams, let g = number(grams), g > 0 { entry.setAmount(g, unit: "g") }
            if !isGrams { entry.setAmount(amount, unit: "serving") }
        }
        // Fields left as displayed keep their exact value (no rounding drift); typed ones win.
        let untouched = Nutrition(kcal: shown.kcal, protein: shown.protein, carbs: shown.carbs, fat: shown.fat)
        entry.kcal = kcal == "\(Int(untouched.kcal.rounded()))" ? untouched.kcal : number(kcal) ?? untouched.kcal
        entry.protein = protein == untouched.protein.formatted(.number.precision(.fractionLength(0...1))) ? untouched.protein : number(protein) ?? untouched.protein
        entry.carbs = carbs == untouched.carbs.formatted(.number.precision(.fractionLength(0...1))) ? untouched.carbs : number(carbs) ?? untouched.carbs
        entry.fat = fat == untouched.fat.formatted(.number.precision(.fractionLength(0...1))) ? untouched.fat : number(fat) ?? untouched.fat

        saving = true
        Task {
            // Health samples can't be edited: replace the old one.
            if let old = entry.healthUUID { await health.delete(healthUUID: old) }
            entry.healthUUID = await health.save(entry)
            saving = false
            dismiss()
        }
    }
}
