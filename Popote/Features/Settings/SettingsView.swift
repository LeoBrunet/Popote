import SwiftUI

struct SettingsView: View {
    @Environment(HealthService.self) private var health
    @Environment(ClaudeSync.self) private var claude
    @Environment(\.dismiss) private var dismiss
    @AppStorage("bringListName") private var bringListName = ""
    @AppStorage("baseKcal") private var baseKcal = 2200.0
    @AppStorage("bodyMass") private var bodyMass = 70.0
    @AppStorage("goal") private var goal = GoalSettings()
    @AppStorage("youtubeAPIKey") private var youtubeKey = ""
    @State private var showBring = false
    @State private var showClaude = false
    @State private var serverText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Bring!") {
                    if Keychain.get("bring.email") != nil {
                        LabeledContent("Account", value: Keychain.get("bring.email") ?? "")
                        Button { showBring = true } label: { LabeledContent("List", value: bringListName.isEmpty ? "—" : bringListName) }
                        Button("Disconnect", role: .destructive) {
                            Task { await BringClient.shared.logout(); bringListName = "" }
                        }
                    } else {
                        Button("Connect Bring!") { showBring = true }
                    }
                }

                Section {
                    if health.connected {
                        Label("Connected", systemImage: "heart.fill").foregroundStyle(Theme.health)
                        if let basal = health.basalPerDay { LabeledContent("Resting energy", value: "\(Int(basal)) kcal/day") }
                        if let mass = health.bodyMass { LabeledContent("Weight", value: "\(mass.formatted(.number.precision(.fractionLength(1)))) kg") }
                    } else {
                        Button("Connect Apple Health") { Task { await health.connect() } }
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("Popote saves each meal (calories, protein, carbs, fat) and reads your energy burned and weight to set the daily target.")
                }

                Section {
                    NavigationLink { GoalView() } label: { LabeledContent("Goal", value: goal.title) }
                    Stepper(value: $baseKcal, in: 1200...4000, step: 50) { LabeledContent("Base target", value: "\(Int(baseKcal)) kcal") }
                    Stepper(value: $bodyMass, in: 40...150, step: 0.5) {
                        LabeledContent("Weight", value: "\(bodyMass.formatted(.number.precision(.fractionLength(1)))) kg")
                    }
                } header: {
                    Text("Targets")
                } footer: {
                    Text("Each day's target follows your goal and your Coach plan. Base target and weight are used only when Apple Health has no data.")
                }

                Section {
                    Button { showClaude = true } label: {
                        LabeledContent("Connector", value: claude.claudeConnected ? String(localized: "Connected") : String(localized: "Set up"))
                    }
                    HStack {
                        TextField("Server", text: $serverText)
                            .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(.footnote.monospaced())
                        Button("Save") {
                            if let url = URL(string: serverText), url.host() != nil {
                                claude.serverURL = url
                                Task { await claude.resetRegistration() }
                            }
                        }
                        .disabled(serverText == claude.serverURL.absoluteString)
                    }
                } header: {
                    Text("Claude")
                } footer: {
                    Text("Claude works in the Claude app with your own plan, through the Popote connector, like the Coach app. Changing the server creates a new connector link.")
                }

                Section {
                    SecureField("YouTube Data API key (optional)", text: $youtubeKey)
                } header: {
                    Text("Import")
                } footer: {
                    Text("Without a key, Popote reads the video description from the YouTube page, which can fail. Captions are read on the iPhone with Apple Intelligence when it's on.")
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                    Text("Nutrition: average values per 100 g (Ciqual, USDA) and Open Food Facts (ODbL).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showBring) { BringConnectView() }
            .sheet(isPresented: $showClaude) { ConnectClaudeView() }
            .onAppear { serverText = claude.serverURL.absoluteString }
        }
    }
}
