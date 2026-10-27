import Foundation

enum HTTP {
    static let safari = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
    static let crawler = "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)"

    struct Page {
        let html: String
        let url: URL          // after redirects (vm.tiktok.com → tiktok.com/@…/video/…)
    }

    static func get(_ url: URL, userAgent: String = safari, cookie: String? = nil) async throws -> Page {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("fr-FR,fr;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        if let cookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw ImportError.http(http.statusCode)
        }
        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return Page(html: html, url: response.url ?? url)
    }

    static func json(_ url: URL, userAgent: String = safari) async throws -> Any {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ImportError.http(http.statusCode)
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func data(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(safari, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}

enum ImportError: LocalizedError {
    case http(Int)
    case nothingFound

    var errorDescription: String? {
        switch self {
        case .http(let code): String(localized: "The page couldn't be loaded (error \(code)).")
        case .nothingFound: String(localized: "No recipe found at this link.")
        }
    }
}

enum HTML {
    /// `<meta property="og:title" content="…">`, in either attribute order.
    static func meta(_ html: String, _ name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        let patterns = [
            "<meta[^>]+(?:property|name)=[\"']\(escaped)[\"'][^>]*content=[\"']([^\"']*)[\"']",
            "<meta[^>]+content=[\"']([^\"']*)[\"'][^>]*(?:property|name)=[\"']\(escaped)[\"']",
        ]
        for pattern in patterns {
            if let value = firstGroup(html, pattern), !value.isEmpty { return decodeEntities(value) }
        }
        return nil
    }

    static func jsonLD(_ html: String) -> [Any] {
        allGroups(html, "<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>([\\s\\S]*?)</script>")
            .compactMap { block in
                let trimmed = block.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) }
            }
    }

    static func firstGroup(_ text: String, _ pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    static func allGroups(_ text: String, _ pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        let named = ["&amp;": "&", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " ",
                     "&rsquo;": "’", "&lsquo;": "‘", "&eacute;": "é", "&egrave;": "è", "&agrave;": "à", "&ccedil;": "ç",
                     "&ecirc;": "ê", "&ocirc;": "ô", "&icirc;": "î", "&ucirc;": "û", "&oelig;": "œ", "&deg;": "°", "&hellip;": "…"]
        for (entity, char) in named { result = result.replacingOccurrences(of: entity, with: char) }
        // Numeric entities: &#233; &#x1F60B;
        while let match = result.firstMatch(of: /&#(x?)([0-9a-fA-F]+);/) {
            let value = match.1.isEmpty ? UInt32(match.2, radix: 10) : UInt32(match.2, radix: 16)
            let char = value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? ""
            result.replaceSubrange(match.range, with: char)
        }
        return result
    }

    /// Plain text of an HTML fragment, keeping line breaks.
    static func text(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "</(p|div|li|h\\d)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(text)
    }
}
