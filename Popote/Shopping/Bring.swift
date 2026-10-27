import Foundation
import Security

/// Bring! has no public API. This talks to the same private API as their web app
/// (as in the open-source `bring-api` / `node-bring-api` clients). It may break after a Bring! update.
actor BringClient {
    static let shared = BringClient()

    private let base = URL(string: "https://api.getbring.com/rest/v2/")!
    private let apiKey = "cof4Nc6D8saplXjE3h3HXqHH8m7VU2i1Gs0g85Sp"   // public key of the Bring! web app
    private var session: Session?
    private var translations: [String: String] = [:]                  // German catalog key → localized name
    private var translationsLocale = ""

    struct Session: Codable {
        var uuid: String
        var publicUuid: String?
        var accessToken: String
        var name: String?
    }

    struct BringList: Identifiable, Hashable { let id: String; let name: String }

    struct ListItem: Hashable {
        let uuid: String?
        let itemId: String         // catalog key ("Zitrone") or free text
        let specification: String
        let displayName: String
    }

    enum BringError: LocalizedError {
        case notConnected, badLogin, server(Int)
        var errorDescription: String? {
            switch self {
            case .notConnected: String(localized: "Connect your Bring! account first.")
            case .badLogin: String(localized: "Wrong email or password.")
            case .server(let code): String(localized: "Bring! didn't answer as expected (error \(code)).")
            }
        }
    }

    // MARK: Account

    func login(email: String, password: String) async throws -> Session {
        var request = request("bringauth", method: "POST")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "email", value: email), .init(name: "password", value: password)]
        request.httpBody = form.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw status == 401 || status == 404 ? BringError.badLogin : BringError.server(status) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        guard let uuid = json["uuid"] as? String, let token = json["access_token"] as? String else { throw BringError.badLogin }
        let session = Session(uuid: uuid, publicUuid: json["publicUuid"] as? String, accessToken: token, name: json["name"] as? String)
        self.session = session
        Keychain.set(email, for: "bring.email")
        Keychain.set(password, for: "bring.password")
        return session
    }

    func logout() {
        session = nil
        Keychain.delete("bring.email")
        Keychain.delete("bring.password")
        UserDefaults.standard.removeObject(forKey: "bringListUUID")
        UserDefaults.standard.removeObject(forKey: "bringListName")
    }

    /// Logs in again with the saved credentials when the app restarted.
    private func ensureSession() async throws -> Session {
        if let session { return session }
        guard let email = Keychain.get("bring.email"), let password = Keychain.get("bring.password") else { throw BringError.notConnected }
        return try await login(email: email, password: password)
    }

    // MARK: Lists

    func lists() async throws -> [BringList] {
        let session = try await ensureSession()
        let json = try await send(request("bringusers/\(session.uuid)/lists", session: session))
        return (json["lists"] as? [[String: Any]] ?? []).compactMap { list in
            guard let id = list["listUuid"] as? String else { return nil }
            return BringList(id: id, name: list["name"] as? String ?? "Bring!")
        }
    }

    func items(list: String) async throws -> [ListItem] {
        let session = try await ensureSession()
        try await loadTranslations(session: session, list: list)
        let json = try await send(request("bringlists/\(list)", session: session))
        let purchase = (json["items"] as? [String: Any])?["purchase"] as? [[String: Any]] ?? []
        return purchase.compactMap { item in
            guard let itemId = item["itemId"] as? String ?? item["name"] as? String else { return nil }
            return ListItem(uuid: item["uuid"] as? String, itemId: itemId,
                            specification: item["specification"] as? String ?? "",
                            displayName: translations[itemId] ?? itemId)
        }
    }

    /// Catalog key for a name in the list's language ("Citron" → "Zitrone"), if Bring! knows it.
    func catalogKey(for names: [String]) -> String? {
        let keys = Set(names.map(TextKey.key))
        return translations.first { keys.contains(TextKey.key($0.value)) }?.key
            ?? translations.keys.first { keys.contains(TextKey.key($0)) }
    }

    func displayName(_ itemId: String) -> String { translations[itemId] ?? itemId }

    /// Adds or updates items in one call. Never removes anything.
    func apply(_ changes: [BringMerge.Change], list: String) async throws {
        let session = try await ensureSession()
        let body: [[String: Any]] = changes.compactMap { change in
            switch change.kind {
            case .add: ["itemId": change.itemId, "spec": change.newSpec, "uuid": UUID().uuidString.lowercased(), "operation": "TO_PURCHASE"]
            case .update: ["itemId": change.itemId, "spec": change.newSpec, "uuid": change.existingUUID ?? "", "operation": "TO_PURCHASE"]
            case .already: nil
            }
        }
        guard !body.isEmpty else { return }
        var request = request("bringlists/\(list)/items", method: "PUT", session: session)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["changes": body, "sender": ""])
        let (_, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw BringError.server(status) }
    }

    private func loadTranslations(session: Session, list: String) async throws {
        var locale = "fr-FR"
        if let settings = try? await send(request("bringusersettings/\(session.uuid)", session: session)),
           let lists = settings["userlistsettings"] as? [[String: Any]],
           let entry = lists.first(where: { $0["listUuid"] as? String == list }),
           let values = entry["usersettings"] as? [[String: Any]],
           let language = values.first(where: { $0["key"] as? String == "listArticleLanguage" })?["value"] as? String {
            locale = language
        }
        guard locale != translationsLocale else { return }
        if locale == "de-DE" { translations = [:]; translationsLocale = locale; return }   // keys are already German
        let url = URL(string: "https://web.getbring.com/locale/articles.\(locale).json")!
        if let json = try? await HTTP.json(url) as? [String: Any] {
            translations = json.compactMapValues { $0 as? String }
            translationsLocale = locale
        }
    }

    // MARK: Plumbing

    private func request(_ path: String, method: String = "GET", session: Session? = nil) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent(path), timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: "X-BRING-API-KEY")
        request.setValue("webApp", forHTTPHeaderField: "X-BRING-CLIENT")
        request.setValue("webApp", forHTTPHeaderField: "X-BRING-CLIENT-SOURCE")
        request.setValue("FR", forHTTPHeaderField: "X-BRING-COUNTRY")
        if let session {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue(session.uuid, forHTTPHeaderField: "X-BRING-USER-UUID")
            if let publicUuid = session.publicUuid { request.setValue(publicUuid, forHTTPHeaderField: "X-BRING-PUBLIC-USER-UUID") }
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { session = nil }
        guard status == 200 else { throw BringError.server(status) }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }
}

/// Popote's list vs what's already on the Bring! list.
enum BringMerge {
    struct Change: Identifiable, Hashable {
        enum Kind { case add, update, already }
        var id: String { itemId + kind.hashValue.description }
        let kind: Kind
        let name: String
        let itemId: String
        let oldSpec: String
        let newSpec: String
        let existingUUID: String?
    }

    static func plan(items: [ShoppingItem], existing: [BringClient.ListItem], client: BringClient) async -> [Change] {
        var changes: [Change] = []
        for item in items {
            let food = FoodTable.byID[item.key]
            let names = [item.name] + (food.map { [$0.fr, $0.en] + $0.aliases } ?? [])
            let catalog = await client.catalogKey(for: names)
            let match = existing.first { entry in
                if let catalog, entry.itemId == catalog { return true }
                if TextKey.key(entry.displayName) == TextKey.key(item.name) { return true }
                if let food, FoodTable.match(entry.displayName)?.id == food.id { return true }
                return false
            }
            if let match {
                if match.specification.isEmpty || item.quantity.isEmpty {
                    changes.append(Change(kind: .already, name: item.name, itemId: match.itemId, oldSpec: match.specification,
                                          newSpec: match.specification, existingUUID: match.uuid))
                } else {
                    changes.append(Change(kind: .update, name: item.name, itemId: match.itemId, oldSpec: match.specification,
                                          newSpec: combine(match.specification, item.quantity), existingUUID: match.uuid))
                }
            } else {
                changes.append(Change(kind: .add, name: item.name, itemId: catalog ?? item.name, oldSpec: "",
                                      newSpec: item.quantity, existingUUID: nil))
            }
        }
        return changes
    }

    /// "1" + "3" → "4", "200 g" + "400 g" → "600 g", otherwise "2 + 400 g".
    static func combine(_ old: String, _ new: String) -> String {
        func split(_ s: String) -> (Double, String)? {
            guard let m = s.trimmingCharacters(in: .whitespaces).firstMatch(of: /^(\d+(?:[.,]\d+)?)\s*([a-zA-Zé]*)$/),
                  let v = Double(m.1.replacingOccurrences(of: ",", with: ".")) else { return nil }
            return (v, String(m.2).lowercased())
        }
        if let a = split(old), let b = split(new), a.1 == b.1 {
            let total = Units.formatNumber(a.0 + b.0)
            return a.1.isEmpty ? total : "\(total) \(a.1)"
        }
        return "\(old) + \(new)"
    }
}

enum Keychain {
    static func set(_ value: String, for key: String) {
        delete(key)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                    kSecValueData as String: Data(value.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key] as CFDictionary)
    }
}
