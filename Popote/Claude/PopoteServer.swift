import Foundation
import UIKit

/// Talks to the Popote server (server/src/api.ts): it stores what the app shares with Claude,
/// and what Claude writes back through the MCP connector.
struct PopoteServer {
    var baseURL: URL
    var token: String?

    static var defaultURL: URL {
        let value = Bundle.main.object(forInfoDictionaryKey: "PopoteServerURL") as? String
        return value.flatMap(URL.init(string:)) ?? URL(string: "http://localhost:8788")!
    }

    enum ServerError: LocalizedError {
        case http(Int, String)
        var errorDescription: String? {
            switch self {
            case .http(let code, let body): String(localized: "Server error (\(code)): \(String(body.prefix(200)))")
            }
        }
    }

    struct Registration: Decodable { let appToken: String; let connectorUrl: String }
    struct ClaudeStatus: Decodable { let connectedAt: String?; let lastSeenAt: String? }
    struct Me: Decodable { let connectorUrl: String; let claude: ClaudeStatus }

    struct Macros: Codable { var kcal: Double; var protein: Double; var carbs: Double; var fat: Double }

    struct Context: Encodable {
        var language: String
        var timezone: String
        var today: String
        var pantry: [String]
        var recipes: [String]
        var targets: Macros
        var eaten: Macros
        var goal: String?
        var journal: [JournalItem] = []
        var recipeDetails: [RecipeItem] = []

        struct Ingredient: Encodable {
            var name: String
            var quantity: Double?
            var unit: String?
            var grams: Double?
            var kcal: Double?
            var product: String?
        }

        struct JournalItem: Encodable {
            var date: String
            var meal: String
            var title: String
            var amount: String?
            var recipe: String?
            var kcal: Double
            var protein: Double
            var carbs: Double
            var fat: Double
            var ingredients: [Ingredient]?
        }

        struct RecipeItem: Encodable {
            var title: String
            var servings: Int
            var minutes: Int?
            var source: String?
            var url: String?
            var createdAt: String?
            var inShoppingList: Bool?
            var perServing: Macros?
            var ingredients: [Ingredient]
            var steps: [String]
        }
    }

    struct Inbox: Decodable {
        struct Ingredient: Decodable {
            let name: String
            let quantity: Double
            let unit: String
            let grams: Double
            let kcal: Double
            let protein: Double
            let carbs: Double
            let fat: Double
        }
        struct MealAnalysis: Decodable { let requestId: String; let title: String; let ingredients: [Ingredient] }
        struct RecipeIngredient: Decodable { let quantity: Double; let unit: String; let name: String; let inPantry: Bool? }
        struct Recipe: Decodable {
            let id: String
            let title: String
            let servings: Int
            let minutes: Int?
            let summary: String?
            let ingredients: [RecipeIngredient]
            let steps: [String]
        }
        let mealAnalyses: [MealAnalysis]
        let recipes: [Recipe]
    }

    func register() async throws -> Registration { try await send("POST", "/api/register", body: Optional<String>.none, authenticated: false) }
    func me() async throws -> Me { try await send("GET", "/api/me", body: Optional<String>.none) }

    func putContext(_ context: Context) async throws {
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await send("PUT", "/api/context", body: context)
    }

    func createMealRequest(meal: String, description: String?, photo: Data?) async throws -> String {
        struct Body: Encodable { let meal: String; let description: String?; let photoBase64: String? }
        struct Created: Decodable { let id: String }
        let created: Created = try await send("POST", "/api/meal-requests",
                                              body: Body(meal: meal, description: description, photoBase64: photo?.base64EncodedString()))
        return created.id
    }

    func inbox() async throws -> Inbox { try await send("GET", "/api/inbox", body: Optional<String>.none) }

    func acknowledge(mealRequests: [String], recipes: [String]) async throws {
        struct Body: Encodable { let mealRequests: [String]; let recipes: [String] }
        struct OK: Decodable { let ok: Bool }
        let _: OK = try await send("POST", "/api/inbox/ack", body: Body(mealRequests: mealRequests, recipes: recipes))
    }

    private func send<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?, authenticated: Bool = true) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONEncoder().encode(body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw ServerError.http(status, String(decoding: data, as: UTF8.self)) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

/// Claude lives in the Claude app (the user's own plan, via the Popote connector).
/// These helpers open Claude with a ready-to-send message.
enum ClaudeLink {
    static func open(_ prompt: String) {
        var components = URLComponents(string: "https://claude.ai/new")!
        components.queryItems = [URLQueryItem(name: "q", value: prompt)]
        // Also on the clipboard, in case the prefill isn't honored.
        UIPasteboard.general.string = prompt
        if let url = components.url { UIApplication.shared.open(url) }
    }

    static func analyzeMeal(_ requestId: String) -> String {
        String(localized: "Analyze my meal in Popote (request \(requestId)): call get_meal_request, then save the ingredients with save_meal_analysis.")
    }

    static func createRecipe(_ request: String, usePantry: Bool, useTargets: Bool) -> String {
        var prompt = String(localized: "Create a recipe for Popote: \(request)")
        if usePantry || useTargets {
            prompt += " " + (usePantry && useTargets ? String(localized: "Use my pantry and what's left of today's targets (get_context).")
                             : usePantry ? String(localized: "Use my pantry (get_context).")
                             : String(localized: "Use what's left of today's targets (get_context)."))
        }
        return prompt + " " + String(localized: "Show it to me, then add it with save_recipe.")
    }

    static let firstHello = String(localized: "Hi! I just connected Popote. Call get_context and tell me in two sentences what you can do for me.")
}
