import SwiftUI

/// One-time setup: add Popote as a custom connector in the Claude app (same model as the Coach app).
struct ConnectClaudeView: View {
    @Environment(ClaudeSync.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DS.Spacing.l) {
                    HStack(spacing: DS.Spacing.s) {
                        ClaudeMark(size: 44)
                        AppMark(size: 44)
                    }
                    .frame(maxWidth: .infinity)
                    Text("Claude does the thinking in the Claude app, with your own plan. Popote gives it your pantry and targets, and receives what it creates.")
                        .font(.subheadline).foregroundStyle(.secondary)

                    step(1, "Copy your connector link") {
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(sync.connectorURL ?? String(localized: "Connecting to the Popote server…"))
                                .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                            Button {
                                UIPasteboard.general.string = sync.connectorURL
                                copied = true
                            } label: {
                                Label(copied ? "Copied" : "Copy the link", systemImage: copied ? "checkmark" : "doc.on.doc")
                            }
                            .buttonStyle(.borderedProminent).tint(Theme.accent)
                            .disabled(sync.connectorURL == nil)
                        }
                    }
                    step(2, "Add it in Claude") {
                        Text("Claude › Settings › Connectors › Add custom connector. Name it Popote and paste the link.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    step(3, "Say hello") {
                        Button { ClaudeLink.open(ClaudeLink.firstHello) } label: { Label("Open Claude", systemImage: "arrow.up.forward.app") }
                            .buttonStyle(.bordered).tint(Theme.accent)
                    }

                    HStack {
                        Image(systemName: sync.claudeConnected ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(sync.claudeConnected ? Theme.herb : .secondary)
                        Text(sync.claudeConnected ? "Claude is connected" : "Not connected yet")
                            .font(.subheadline.weight(.semibold))
                    }
                    .card(padding: DS.Spacing.s)

                    if let error = sync.lastError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Theme.accent)
                    }
                    Label("The link contains a secret: anyone who has it can read your pantry and add recipes. Don't share it.",
                          systemImage: "lock")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(DS.Spacing.m)
            }
            .background(Theme.background)
            .navigationTitle("Connect Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await sync.bootstrap() }
        }
    }

    private func step<Content: View>(_ number: Int, _ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.s) {
            Text("\(number)")
                .font(.subheadline.weight(.bold)).foregroundStyle(Theme.onAccent)
                .frame(width: 26, height: 26).background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title).font(.headline)
                content()
            }
            Spacer(minLength: 0)
        }
    }
}
