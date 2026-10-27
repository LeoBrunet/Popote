import PhotosUI
import SwiftData
import SwiftUI

/// The + button (and each meal's "Add"): describe what you ate, or take a photo, scan, pick a recipe, or re-log a recent food.
struct LogMealSheet: View {
    var meal: Meal = .now
    var day = Date()

    @Environment(\.modelContext) private var context
    @Environment(HealthService.self) private var health
    @Environment(ClaudeSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \JournalEntry.date, order: .reverse) private var history: [JournalEntry]
    @Query private var drafts: [MealDraft]
    @State private var sending = false
    @State private var sendError: String?
    @State private var selectedMeal = Meal.now
    @State private var text = ""
    @State private var path: [Step] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var addFood: AddFoodSheet.Mode?
    @FocusState private var fieldFocused: Bool

    enum Step: Hashable { case draft(UUID) }

    /// Last distinct things logged, to add again in one tap.
    private var recents: [JournalEntry] {
        var seen = Set<String>()
        return history.filter { seen.insert($0.title).inserted }.prefix(6).map { $0 }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.m) {
                    mealPicker
                    describeField
                    HStack {
                        action("Photo", "camera.fill") {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) { showCamera = true } else { showLibrary = true }
                        }
                        action("Scan", "barcode.viewfinder") { addFood = .scan }
                        action("My recipes", "book.fill") { addFood = .recipe }
                    }
                    if !recents.isEmpty { recentList }
                }
                .padding(DS.Spacing.m)
            }
            .background(Theme.background)
            .navigationTitle("Add a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    PhotosPicker(selection: $photoItem, matching: .images) { Image(systemName: "photo.on.rectangle") }
                        .accessibilityLabel("Choose a photo")
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .draft(let id):
                    if let draft = drafts.first(where: { $0.id == id }) { DescribeMealView(draft: draft) { dismiss() } }
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in photoChosen(image) }.ignoresSafeArea()
            }
            .sheet(item: $addFood) { mode in AddFoodSheet(meal: selectedMeal, day: day, initialMode: mode) }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) { photoChosen(image) }
                    photoItem = nil
                }
            }
        }
        .onAppear { selectedMeal = meal }
    }

    private var mealPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Meal.allCases) { item in
                    Button { selectedMeal = item } label: { Chip(text: item.name, selected: item == selectedMeal) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var describeField: some View {
        VStack(alignment: .trailing, spacing: DS.Spacing.s) {
            TextField("What did you eat?", text: $text, axis: .vertical)
                .lineLimit(3...6)
                .focused($fieldFocused)
                .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { send(text: text, photo: nil) } label: {
                    if sending { ProgressView().tint(.white) } else { Label("Ask Claude", systemImage: "sparkle") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending)
            }
            if let sendError { Text(sendError).font(.caption).foregroundStyle(Theme.accent).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .card()
    }

    private func action(_ title: LocalizedStringKey, _ icon: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 54, height: 54)
                    .background(Theme.accentSoft, in: Circle())
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Color.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
            Text("Recent").font(.headline)
            VStack(spacing: 0) {
                ForEach(recents) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title).font(.subheadline).lineLimit(1)
                            Text("\(entry.detail) · \(Int(entry.kcal)) kcal").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { logAgain(entry) } label: {
                            Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.accent)
                        }
                        .accessibilityLabel("Add again")
                    }
                    .padding(.vertical, 7)
                    if entry.id != recents.last?.id { Divider() }
                }
            }
            .card(padding: DS.Spacing.s)
        }
    }

    private func photoChosen(_ image: UIImage) {
        send(text: text, photo: image.mealJPEG())
    }

    /// Sends the meal to the Popote server and opens Claude on it; the screen then waits for the ingredients.
    private func send(text: String, photo: Data?) {
        sending = true
        sendError = nil
        Task {
            do {
                let draft = try await sync.sendMeal(text: text.trimmingCharacters(in: .whitespacesAndNewlines), photo: photo,
                                                    meal: selectedMeal, day: day, context: context)
                path.append(.draft(draft.id))
            } catch {
                sendError = String(localized: "Couldn't reach the Popote server: \(error.localizedDescription)")
            }
            sending = false
        }
    }

    private func logAgain(_ old: JournalEntry) {
        let date = Calendar.current.isDateInToday(day) ? Date() : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
        let entry = JournalEntry(date: date, meal: selectedMeal, title: old.title, detail: old.detail, nutrition: old.nutrition)
        entry.amount = old.amount
        entry.amountUnit = old.amountUnit
        entry.recipeID = old.recipeID
        entry.linesData = old.linesData
        context.insert(entry)
        try? context.save()
        Task {
            entry.healthUUID = await health.save(entry)
            try? context.save()
            dismiss()
        }
    }
}

extension AddFoodSheet.Mode: Identifiable {
    var id: Self { self }
}

extension UIImage {
    /// Downscaled JPEG to send to Claude (long side ≤ 1280 px).
    func mealJPEG() -> Data? {
        let scale = min(1, 1280 / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let resized = UIGraphicsImageRenderer(size: target).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: 0.8)
    }
}

/// System camera.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
