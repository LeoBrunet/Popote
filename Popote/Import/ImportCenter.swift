import Foundation
import Observation
import SwiftData

/// Imports links (from the share extension, a pasted link, or typed) into recipes.
@MainActor
@Observable
final class ImportCenter {
    struct Job: Identifiable {
        enum State: Equatable { case running, done(UUID), failed(String) }
        let id: UUID
        let url: URL
        var state = State.running
        var title: String?
    }

    var jobs: [Job] = []

    /// Links waiting in the App Group inbox (shared while the app was closed).
    func processInbox(context: ModelContext) {
        for item in SharedInbox.load() {
            guard let url = URL(string: item.url), !jobs.contains(where: { $0.id == item.id }) else { continue }
            start(url: url, text: item.text, id: item.id, context: context)
        }
    }

    func start(url: URL, text: String? = nil, id: UUID = UUID(), context: ModelContext) {
        // Same link shared twice (share sheet + pasted, or a retry): open the recipe we already have.
        if jobs.contains(where: { $0.url == url && $0.state == .running }) { SharedInbox.remove(id); return }
        if let existing = existingRecipe(url.absoluteString, context: context) {
            SharedInbox.remove(id)
            finish(Job(id: id, url: url, state: .done(existing.id), title: existing.title))
            return
        }
        jobs.append(Job(id: id, url: url))
        Task {
            do {
                let recipe = try await RecipeImporter.importRecipe(from: url, sharedText: text)
                if let existing = existingRecipe(recipe.sourceURL, context: context) {
                    update(id) { $0.state = .done(existing.id); $0.title = existing.title }
                } else {
                    context.insert(recipe)
                    try? context.save()
                    update(id) { $0.state = .done(recipe.id); $0.title = recipe.title }
                }
                autoDismiss(id)
            } catch {
                update(id) { $0.state = .failed(error.localizedDescription) }
            }
            SharedInbox.remove(id)
        }
    }

    private func existingRecipe(_ url: String, context: ModelContext) -> Recipe? {
        guard !url.isEmpty else { return nil }
        let descriptor = FetchDescriptor<Recipe>(predicate: #Predicate { $0.sourceURL == url })
        return try? context.fetch(descriptor).first
    }

    private func finish(_ job: Job) {
        jobs.removeAll { $0.url == job.url }
        jobs.append(job)
        autoDismiss(job.id)
    }

    /// "Recipe ready" banners go away on their own.
    private func autoDismiss(_ id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(8))
            dismiss(id)
        }
    }

    func dismiss(_ id: UUID) { jobs.removeAll { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[i])
    }
}

enum RecipeImporter {
    static func importRecipe(from url: URL, sharedText: String?) async throws -> Recipe {
        var imported: ImportedRecipe
        switch SourceDetector.source(url) {
        case .youtube: imported = try await Extractors.youtube(url)
        case .tiktok: imported = try await Extractors.tiktok(url)
        case .instagram: imported = try await Extractors.instagram(url)
        case .web, .manual, .claude: imported = try await Extractors.web(url)
        }
        if let sharedText, sharedText.count > (imported.rawText?.count ?? 0) { imported.rawText = sharedText }

        if imported.ingredients.isEmpty, let text = imported.rawText, !text.isEmpty {
            let structured = await RecipeStructurer.structure(text)
            imported.ingredients = structured.ingredients
            imported.steps = structured.steps
            imported.servings = structured.servings ?? imported.servings
            imported.minutes = imported.minutes ?? structured.minutes
            if imported.title.isEmpty, let title = structured.title { imported.title = title }
            imported.guessed = true
        }
        guard !imported.title.isEmpty || !imported.ingredients.isEmpty || imported.videoID != nil else {
            throw ImportError.nothingFound
        }

        let recipe = Recipe(title: imported.title.isEmpty ? String(localized: "New recipe") : imported.title,
                            source: imported.source, url: imported.url)
        recipe.author = imported.author
        recipe.videoID = imported.videoID
        recipe.imageURL = imported.imageURL
        recipe.minutes = imported.minutes
        recipe.servings = imported.servings
        recipe.shoppingServings = imported.servings
        recipe.ingredients = imported.ingredients
        recipe.steps = imported.steps
        recipe.rawText = imported.rawText
        recipe.needsReview = imported.guessed || imported.ingredients.isEmpty
        // Instagram and TikTok picture links expire: keep a copy.
        if let image = imported.imageURL.flatMap(URL.init(string:)) {
            recipe.imageData = await HTTP.data(image)
        }
        return recipe
    }
}
