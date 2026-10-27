import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share sheet entry point: grabs the shared link (and any caption text), drops it in the
/// shared inbox and closes. The app imports it the next time it comes to the foreground.
final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let host = UIHostingController(rootView: ShareCard(model: model) { [weak self] in self?.finish() })
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        Task { @MainActor in
            await model.load(items)
            if case .saved = model.state {
                try? await Task.sleep(for: .seconds(1.4))
                finish()
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}

@MainActor
final class ShareModel: ObservableObject {
    enum State { case loading, saved(host: String), failed }
    @Published var state = State.loading

    func load(_ items: [NSExtensionItem]) async {
        var url: URL?
        var texts: [String] = []
        for item in items {
            if let text = item.attributedContentText?.string, !text.isEmpty { texts.append(text) }
            for provider in item.attachments ?? [] {
                if url == nil, provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let value = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) {
                    url = (value as? URL) ?? (value as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          let value = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                          let text = value as? String {
                    texts.append(text)
                }
            }
        }
        let text = texts.joined(separator: "\n")
        if url == nil || url?.isFileURL == true { url = SharedInbox.firstURL(in: text) }
        guard let url else { state = .failed; return }
        let caption = text.replacingOccurrences(of: url.absoluteString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        SharedInbox.add(.init(url: url.absoluteString, text: caption.isEmpty ? nil : caption))
        state = .saved(host: url.host()?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString)
    }
}

private struct ShareCard: View {
    @ObservedObject var model: ShareModel
    let close: () -> Void
    private let accent = Color(red: 0.88, green: 0.33, blue: 0.22)

    var body: some View {
        VStack {
            Spacer()
            VStack(spacing: 14) {
                switch model.state {
                case .loading:
                    ProgressView()
                    Text("Sending to Popote…").font(.headline)
                case .saved(let host):
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(accent)
                    Text("Saved to Popote").font(.headline)
                    Text("The recipe from \(host) will be ready when you open Popote.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                case .failed:
                    Image(systemName: "link.badge.plus").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("No link found").font(.headline)
                    Text("Share a recipe link from Instagram, YouTube, TikTok or a website.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Close", action: close).buttonStyle(.borderedProminent).tint(accent)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding()
        }
    }
}
