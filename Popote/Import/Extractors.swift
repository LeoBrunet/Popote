import Foundation

/// What we got out of a link before structuring.
struct ImportedRecipe {
    var source: RecipeSource
    var url: String
    var title = ""
    var author = ""
    var videoID: String?
    var imageURL: String?
    var minutes: Int?
    var servings = 2
    var ingredients: [IngredientLine] = []
    var steps: [RecipeStep] = []
    var rawText: String?          // caption / description, structured afterwards when needed
    var guessed = false
}

enum SourceDetector {
    static func source(_ url: URL) -> RecipeSource {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("youtube.com") || host.contains("youtu.be") { return .youtube }
        if host.contains("tiktok.com") { return .tiktok }
        if host.contains("instagram.com") { return .instagram }
        return .web
    }

    static func youTubeID(_ url: URL) -> String? {
        let host = url.host()?.lowercased() ?? ""
        if host.contains("youtu.be") { return url.pathComponents.dropFirst().first }
        guard host.contains("youtube") else { return nil }
        if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value { return v }
        let parts = url.pathComponents
        if let i = parts.firstIndex(where: { ["shorts", "embed", "live", "v"].contains($0) }), i + 1 < parts.count { return parts[i + 1] }
        return nil
    }

    static func tikTokID(_ url: URL) -> String? {
        url.absoluteString.firstMatch(of: /\/(?:video|photo)\/(\d+)/).map { String($0.1) }
    }

    static func instagramCode(_ url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.firstIndex(where: { ["p", "reel", "reels", "tv"].contains($0) }), i + 1 < parts.count else { return nil }
        return parts[i + 1]
    }

    /// Start time encoded in a YouTube link (?t=90 / &t=1m30s).
    static func youTubeStart(_ url: URL) -> Int? {
        guard let t = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value else { return nil }
        if let seconds = Int(t.trimmingCharacters(in: CharacterSet(charactersIn: "s"))) { return seconds }
        guard let match = t.firstMatch(of: /(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?/) else { return nil }
        return (match.1.flatMap { Int($0) } ?? 0) * 3600 + (match.2.flatMap { Int($0) } ?? 0) * 60 + (match.3.flatMap { Int($0) } ?? 0)
    }
}

enum Extractors {
    static func web(_ url: URL) async throws -> ImportedRecipe {
        let page = try await HTTP.get(url)
        if let object = JSONLDRecipe.find(in: HTML.jsonLD(page.html)) {
            var recipe = JSONLDRecipe.parse(object, url: page.url)
            if recipe.imageURL == nil { recipe.imageURL = HTML.meta(page.html, "og:image") }
            if !recipe.ingredients.isEmpty { return recipe }
        }
        // No structured data: keep the page's description and main text for the structurer.
        var recipe = ImportedRecipe(source: .web, url: page.url.absoluteString)
        recipe.title = HTML.meta(page.html, "og:title") ?? HTML.firstGroup(page.html, "<title>([^<]*)</title>").map(HTML.decodeEntities) ?? ""
        recipe.imageURL = HTML.meta(page.html, "og:image")
        recipe.author = HTML.meta(page.html, "og:site_name") ?? url.host()?.replacingOccurrences(of: "www.", with: "") ?? ""
        let body = HTML.firstGroup(page.html, "<article[^>]*>([\\s\\S]*?)</article>")
            ?? HTML.firstGroup(page.html, "<main[^>]*>([\\s\\S]*?)</main>")
            ?? ""
        let cleaned = body.replacingOccurrences(of: "<(script|style)[\\s\\S]*?</\\1>", with: "", options: .regularExpression)
        recipe.rawText = [HTML.meta(page.html, "og:description"), HTML.text(cleaned)]
            .compactMap { $0 }.joined(separator: "\n")
        return recipe
    }

    static func youtube(_ url: URL) async throws -> ImportedRecipe {
        guard let id = SourceDetector.youTubeID(url) else { throw ImportError.nothingFound }
        var recipe = ImportedRecipe(source: .youtube, url: "https://www.youtube.com/watch?v=\(id)")
        recipe.videoID = id
        recipe.imageURL = "https://i.ytimg.com/vi/\(id)/hqdefault.jpg"

        var oembed = URLComponents(string: "https://www.youtube.com/oembed")!
        oembed.queryItems = [.init(name: "url", value: recipe.url), .init(name: "format", value: "json")]
        if let json = try? await HTTP.json(oembed.url!) as? [String: Any] {
            recipe.title = json["title"] as? String ?? ""
            recipe.author = json["author_name"] as? String ?? ""
        }
        recipe.rawText = try? await youTubeDescription(id)
        return recipe
    }

    /// Video description: the Data API when a key is set in Settings, otherwise the watch page.
    private static func youTubeDescription(_ id: String) async throws -> String? {
        if let key = UserDefaults.standard.string(forKey: "youtubeAPIKey"), !key.isEmpty {
            var api = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")!
            api.queryItems = [.init(name: "part", value: "snippet"), .init(name: "id", value: id), .init(name: "key", value: key)]
            if let json = try? await HTTP.json(api.url!) as? [String: Any],
               let snippet = (json["items"] as? [[String: Any]])?.first?["snippet"] as? [String: Any] {
                return snippet["description"] as? String
            }
        }
        let page = try await HTTP.get(URL(string: "https://www.youtube.com/watch?v=\(id)&hl=fr")!, userAgent: HTTP.safari.replacingOccurrences(of: "iPhone", with: "Macintosh"),
                                      cookie: "SOCS=CAI; CONSENT=YES+cb")
        guard let escaped = HTML.firstGroup(page.html, "\"shortDescription\":\"((?:[^\"\\\\]|\\\\.)*)\""),
              let data = "\"\(escaped)\"".data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    static func tiktok(_ url: URL) async throws -> ImportedRecipe {
        var recipe = ImportedRecipe(source: .tiktok, url: url.absoluteString)
        var oembed = URLComponents(string: "https://www.tiktok.com/oembed")!
        oembed.queryItems = [.init(name: "url", value: url.absoluteString)]
        if let json = try? await HTTP.json(oembed.url!) as? [String: Any] {
            recipe.rawText = json["title"] as? String
            recipe.author = (json["author_unique_id"] as? String).map { "@" + $0 } ?? json["author_name"] as? String ?? ""
            recipe.imageURL = json["thumbnail_url"] as? String
            recipe.videoID = json["embed_product_id"] as? String
        }
        if recipe.videoID == nil { recipe.videoID = SourceDetector.tikTokID(url) }
        // oEmbed often comes back without the caption: read it from the video page (this also follows short links).
        if recipe.rawText == nil || recipe.videoID == nil, let page = try? await HTTP.get(url) {
            recipe.videoID = recipe.videoID ?? SourceDetector.tikTokID(page.url)
            recipe.url = page.url.absoluteString
            recipe.rawText = recipe.rawText ?? jsonString(page.html, "desc")
            if recipe.author.isEmpty, let user = jsonString(page.html, "uniqueId") { recipe.author = "@" + user }
            recipe.imageURL = recipe.imageURL ?? jsonString(page.html, "cover") ?? HTML.meta(page.html, "og:image")
        }
        guard recipe.videoID != nil || recipe.rawText != nil else { throw ImportError.nothingFound }
        recipe.title = firstLine(recipe.rawText) ?? ""
        return recipe
    }

    /// Instagram: the public post page (as a link-preview crawler) gives the caption and a picture;
    /// the embed page is the fallback. Data stays on the device, for display.
    static func instagram(_ url: URL) async throws -> ImportedRecipe {
        guard let code = SourceDetector.instagramCode(url) else { throw ImportError.nothingFound }
        var recipe = ImportedRecipe(source: .instagram, url: "https://www.instagram.com/p/\(code)/")
        recipe.videoID = code

        if let page = try? await HTTP.get(URL(string: recipe.url)!, userAgent: HTTP.crawler) {
            recipe.imageURL = HTML.meta(page.html, "og:image")
            if let description = HTML.meta(page.html, "og:description") ?? HTML.meta(page.html, "description") {
                // "1 234 likes, 56 comments - julie.popote on March 3, 2026: "Bowl saumon…""
                if let match = description.firstMatch(of: /^(?:.*?) - (?<user>[\w.]+)[\s\u{00A0}]+(?:on|le)[\s\u{00A0}]+[^:]+:\s*[“"]?(?<caption>[\s\S]*?)[”"]?\.?$/) {
                    recipe.author = "@" + match.user
                    recipe.rawText = String(match.caption)
                } else {
                    recipe.rawText = description
                }
            }
        }
        if (recipe.rawText ?? "").count < 80,
           let embed = try? await HTTP.get(URL(string: "https://www.instagram.com/p/\(code)/embed/captioned/")!) {
            if let caption = HTML.firstGroup(embed.html, "<div class=\"Caption\">([\\s\\S]*?)<div class=\"CaptionComments\"") {
                var text = HTML.text(caption).trimmingCharacters(in: .whitespacesAndNewlines)
                if let user = HTML.firstGroup(caption, "class=\"CaptionUsername\"[^>]*>([^<]+)<") {
                    recipe.author = "@" + user
                    if text.hasPrefix(user) { text = String(text.dropFirst(user.count)).trimmingCharacters(in: .whitespacesAndNewlines) }
                }
                recipe.rawText = text
            }
            if recipe.imageURL == nil {
                recipe.imageURL = HTML.firstGroup(embed.html, "class=\"EmbeddedMediaImage\"[^>]*src=\"([^\"]+)\"").map(HTML.decodeEntities)
            }
        }
        recipe.title = firstLine(recipe.rawText) ?? ""
        return recipe
    }

    /// First non-empty `"key":"value"` string in a page's embedded JSON, unescaped.
    static func jsonString(_ html: String, _ key: String) -> String? {
        for escaped in HTML.allGroups(html, "\"\(key)\":\"((?:[^\"\\\\]|\\\\.)+)\"") {
            if let data = "\"\(escaped)\"".data(using: .utf8), let value = try? JSONDecoder().decode(String.self, from: data) {
                return value
            }
        }
        return nil
    }

    /// A caption's first line, without hashtags and emojis, as a title.
    static func firstLine(_ text: String?) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: .newlines)
            .map { IngredientParser.clean($0.replacingOccurrences(of: "#\\S+", with: "", options: .regularExpression)) }
            .first { $0.count > 3 } ?? ""
        let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: " .!:-"))
        return trimmed.count > 70 ? String(trimmed.prefix(67)) + "…" : trimmed
    }
}
