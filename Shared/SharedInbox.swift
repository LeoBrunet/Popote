import Foundation

/// Links handed over by the share extension, waiting for the app to import them.
/// Stored as JSON in the App Group container so both processes can read and write it.
enum SharedInbox {
    static let appGroup = "group.com.leobrunet.popote"

    struct Item: Codable, Identifiable, Equatable {
        var id = UUID()
        var url: String
        var text: String?          // caption or note shared alongside the link
        var date = Date()
    }

    private static var fileURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("inbox.json")
    }

    static func load() -> [Item] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Item].self, from: data)) ?? []
    }

    static func add(_ item: Item) {
        var items = load()
        guard !items.contains(where: { $0.url == item.url }) else { return }
        items.append(item)
        save(items)
    }

    static func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }

    private static func save(_ items: [Item]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// First http(s) link found in free text ("Look at this recipe https://…").
    static func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "http" || $0.scheme == "https" }
    }
}
