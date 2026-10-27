import Foundation
import SwiftUI
import VisionKit

/// Open Food Facts: free product database (barcode → nutrition per 100 g).
enum OpenFoodFacts {
    private static let offAgent = "Popote/0.1 (iOS; personal use)"
    private static let fields = "code,product_name,product_name_fr,product_name_en,brands,nutriments,nutriscore_grade,serving_quantity,image_front_small_url"

    static func product(barcode: String) async throws -> ProductSnapshot? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode)?fields=\(fields)")!
        guard let json = try await HTTP.json(url, userAgent: offAgent) as? [String: Any],
              json["status"] as? Int == 1,                        // 200 OK even when the product is unknown
              let product = json["product"] as? [String: Any] else { return nil }
        return snapshot(product, code: barcode)
    }

    static func search(_ query: String) async throws -> [ProductSnapshot] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "action", value: "process"), .init(name: "json", value: "1"),
            .init(name: "page_size", value: "20"), .init(name: "fields", value: fields),
        ]
        guard let json = try await HTTP.json(components.url!, userAgent: offAgent) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else { return [] }
        return products.compactMap { snapshot($0, code: $0["code"] as? String ?? "") }
    }

    private static func snapshot(_ product: [String: Any], code: String) -> ProductSnapshot? {
        let n = product["nutriments"] as? [String: Any] ?? [:]
        func value(_ key: String) -> Double? {
            (n[key] as? NSNumber)?.doubleValue ?? (n[key] as? String).flatMap(Double.init)
        }
        guard let kcal = value("energy-kcal_100g") ?? value("energy_100g").map({ $0 / 4.184 }) else { return nil }
        let french = Locale.current.language.languageCode?.identifier == "fr"
        let localized = (french ? product["product_name_fr"] : product["product_name_en"]) as? String
        let name = [localized, product["product_name"] as? String].compactMap { $0 }.first { !$0.isEmpty } ?? code
        return ProductSnapshot(
            code: code, name: name,
            brand: (product["brands"] as? String)?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces),
            kcal: kcal, protein: value("proteins_100g") ?? 0, carbs: value("carbohydrates_100g") ?? 0, fat: value("fat_100g") ?? 0,
            nutriScore: (product["nutriscore_grade"] as? String).flatMap { $0.count == 1 ? $0.uppercased() : nil },
            servingGrams: (product["serving_quantity"] as? NSNumber)?.doubleValue ?? (product["serving_quantity"] as? String).flatMap(Double.init),
            imageURL: product["image_front_small_url"] as? String)
    }
}

/// Camera barcode scanner (VisionKit). Falls back to typing the code where the camera isn't available (Simulator).
struct BarcodeScanner: View {
    let onCode: (String) -> Void
    @State private var typed = ""

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ScannerView(onCode: onCode)
                .overlay {
                    RoundedRectangle(cornerRadius: 18).stroke(.white, lineWidth: 3).frame(width: 260, height: 150)
                }
        } else {
            VStack(spacing: DS.Spacing.m) {
                Image(systemName: "barcode.viewfinder").font(.system(size: 54)).foregroundStyle(.secondary)
                Text("The camera isn't available here. Type the barcode instead.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                TextField("3017620422003", text: $typed)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                Button("Look up") { onCode(typed) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .disabled(typed.count < 8)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let barcode) = item, let code = barcode.payloadStringValue {
                    done = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onCode(code)
                    return
                }
            }
        }
    }
}
