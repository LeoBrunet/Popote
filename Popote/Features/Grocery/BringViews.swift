import SwiftUI

/// Log in to Bring! and pick the list to sync with.
struct BringConnectView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bringListUUID") private var listUUID = ""
    @AppStorage("bringListName") private var listName = ""
    @State private var email = Keychain.get("bring.email") ?? ""
    @State private var password = ""
    @State private var lists: [BringClient.BringList] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if lists.isEmpty {
                    Section {
                        TextField("Email", text: $email)
                            .textContentType(.username).keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Bring! password", text: $password).textContentType(.password)
                    } footer: {
                        Text("Signed up with Google or Apple? Set a password in the Bring! app first (Profile › Account).")
                    }
                    Section {
                        Button {
                            Task { await login() }
                        } label: {
                            HStack { Text("Connect"); if loading { Spacer(); ProgressView() } }
                        }
                        .disabled(email.isEmpty || password.isEmpty || loading)
                    }
                } else {
                    Section("Which list?") {
                        ForEach(lists) { list in
                            Button {
                                listUUID = list.id
                                listName = list.name
                                dismiss()
                            } label: {
                                HStack {
                                    Text(list.name).foregroundStyle(Color.primary)
                                    Spacer()
                                    if list.id == listUUID { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                                }
                            }
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(Theme.accent) } }
                Section {
                    Label("Bring! has no public API. Popote uses the same private API as their web app, directly from your iPhone. "
                          + "Your password stays in the iPhone's keychain. A Bring! update can break the sync; the shared text list always works.",
                          systemImage: "exclamationmark.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connect Bring!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .task {
                if Keychain.get("bring.password") != nil { await loadLists() }
            }
        }
    }

    private func login() async {
        loading = true
        error = nil
        do {
            _ = try await BringClient.shared.login(email: email, password: password)
            await loadLists()
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func loadLists() async {
        do {
            lists = try await BringClient.shared.lists()
            if lists.count == 1, let only = lists.first {
                listUUID = only.id
                listName = only.name
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Preview of the merge with the Bring! list, then one batch update.
struct BringSyncView: View {
    let items: [ShoppingItem]
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bringListUUID") private var listUUID = ""
    @AppStorage("bringListName") private var listName = ""
    @State private var changes: [BringMerge.Change] = []
    @State private var others: [BringClient.ListItem] = []
    @State private var state = SyncState.loading
    @State private var showConnect = false

    enum SyncState: Equatable { case loading, ready, sending, sent, failed(String) }

    var body: some View {
        NavigationStack {
            List {
                switch state {
                case .loading:
                    HStack { ProgressView(); Text("Reading \"\(listName)\"…").foregroundStyle(.secondary) }
                case .failed(let message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(Theme.accent)
                        Button("Reconnect Bring!") { showConnect = true }
                        Button("Try again") { Task { await load() } }
                    }
                case .sent:
                    Section {
                        Label("Sent to \"\(listName)\"", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.herb).font(.headline)
                    }
                default:
                    summary
                    group("To add", kind: .add, icon: "plus.circle.fill", color: Theme.herb)
                    group("Quantity to update", kind: .update, icon: "arrow.triangle.2.circlepath.circle.fill", color: Theme.carbs)
                    group("Already on the list", kind: .already, icon: "checkmark.circle", color: .secondary)
                    if !others.isEmpty {
                        Section("Also on \"\(listName)\"") {
                            ForEach(others, id: \.self) { item in
                                HStack {
                                    Text(item.displayName)
                                    Spacer()
                                    Text(item.specification).foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Bring!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(state == .sent ? "Done" : "Cancel") { dismiss() } } }
            .safeAreaInset(edge: .bottom) {
                if state == .ready || state == .sending {
                    let count = changes.filter { $0.kind != .already }.count
                    Button {
                        Task { await send() }
                    } label: {
                        if state == .sending { ProgressView().tint(.white) } else { Text("Send \(count) changes to Bring!") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(count == 0 || state == .sending)
                    .padding()
                    .background(.bar)
                }
            }
            .sheet(isPresented: $showConnect, onDismiss: { Task { await load() } }) { BringConnectView() }
            .task { await load() }
        }
    }

    private var summary: some View {
        Section {
            HStack(spacing: DS.Spacing.l) {
                count(changes.filter { $0.kind == .add }.count, "to add", Theme.herb)
                count(changes.filter { $0.kind == .update }.count, "to update", Theme.carbs)
                count(changes.filter { $0.kind == .already }.count, "already there", .secondary)
            }
            .frame(maxWidth: .infinity)
        } footer: {
            Text("Popote only adds items and updates quantities. Nothing is removed from your list.")
        }
    }

    private func count(_ n: Int, _ label: LocalizedStringKey, _ color: Color) -> some View {
        VStack {
            Text("\(n)").font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, kind: BringMerge.Change.Kind, icon: String, color: Color) -> some View {
        let rows = changes.filter { $0.kind == kind }
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { change in
                    HStack {
                        Image(systemName: icon).foregroundStyle(color)
                        Text(change.name)
                        Spacer()
                        switch kind {
                        case .update: Text("\(change.oldSpec) → \(change.newSpec)").foregroundStyle(.secondary)
                        default: Text(change.newSpec).foregroundStyle(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func load() async {
        state = .loading
        guard !listUUID.isEmpty else { state = .failed(String(localized: "Pick a Bring! list first.")); return }
        do {
            let existing = try await BringClient.shared.items(list: listUUID)
            changes = await BringMerge.plan(items: items, existing: existing, client: BringClient.shared)
            let matched = Set(changes.compactMap(\.existingUUID))
            others = existing.filter { item in item.uuid.map { !matched.contains($0) } ?? !changes.contains { $0.itemId == item.itemId } }
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func send() async {
        state = .sending
        do {
            try await BringClient.shared.apply(changes, list: listUUID)
            state = .sent
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
