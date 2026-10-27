import SwiftUI

/// Recipe picture: the stored copy, the remote image, or a gradient placeholder.
struct RecipePhoto: View {
    let recipe: Recipe
    var symbolSize: CGFloat = 40

    var body: some View {
        // The picture fills the frame it's given and never sizes it (wide photos would widen cards).
        Color.clear.overlay {
            if let data = recipe.imageData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let url = recipe.imageURL.flatMap(URL.init(string:)) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .contentShape(Rectangle())
    }

    private var placeholder: some View {
        LinearGradient(colors: [Theme.accent.opacity(0.55), Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay {
                Image(systemName: "fork.knife")
                    .font(.system(size: symbolSize, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
    }
}

struct SourceBadge: View {
    let source: RecipeSource
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: source.icon).font(.system(size: 9, weight: .bold))
            if !compact { Text(source.name).font(.system(size: 11, weight: .semibold)) }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, 4)
        .background(source.color, in: Capsule())
    }
}

/// Stacked protein / carbs / fat bar (share of calories).
struct MacroBar: View {
    let nutrition: Nutrition
    var height: CGFloat = 8

    var body: some View {
        let p = nutrition.protein * 4, c = nutrition.carbs * 4, f = nutrition.fat * 9
        let total = max(p + c + f, 1)
        GeometryReader { geo in
            HStack(spacing: 2) {
                Theme.protein.frame(width: geo.size.width * p / total)
                Theme.carbs.frame(width: geo.size.width * c / total)
                Theme.fat
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

struct MacroValue: View {
    let label: LocalizedStringKey
    let grams: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Int(grams.rounded())) g").font(.system(.headline, design: .rounded).monospacedDigit())
        }
    }
}

struct MacroSummary: View {
    let nutrition: Nutrition
    var caption: LocalizedStringKey = "kcal / serving"

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(Int(nutrition.kcal.rounded()))").font(.system(size: 34, weight: .bold, design: .rounded))
                Text(caption).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            MacroBar(nutrition: nutrition)
            HStack {
                MacroValue(label: "Protein", grams: nutrition.protein, color: Theme.protein)
                Spacer()
                MacroValue(label: "Carbs", grams: nutrition.carbs, color: Theme.carbs)
                Spacer()
                MacroValue(label: "Fat", grams: nutrition.fat, color: Theme.fat)
            }
        }
    }
}

struct Ring: View {
    let value: Double
    let target: Double
    let color: Color
    var lineWidth: CGFloat = 10

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(value / max(target, 1), 1))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct MatchBadge: View {
    let kind: MatchKind

    var body: some View {
        let (label, icon, color): (LocalizedStringKey, String, Color) = switch kind {
        case .food: ("Checked", "checkmark.seal.fill", Theme.herb)
        case .product: ("Scanned", "barcode", .blue)
        case .estimated: ("Estimated", "sparkles", Theme.carbs)
        case .ignored: ("Not counted", "minus.circle", .secondary)
        case .missing: ("To complete", "exclamationmark.triangle.fill", Theme.accent)
        }
        Label(label, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct Chip: View {
    let text: LocalizedStringKey
    var selected = false
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? Theme.onAccent : .primary)
        .background(selected ? Theme.accent : Theme.card, in: Capsule())
        .overlay { if !selected { Capsule().stroke(Color.primary.opacity(0.1)) } }
    }
}

/// Large serif title with an optional round icon button, as in the mockups.
struct ScreenHeader<Trailing: View>: View {
    let title: LocalizedStringKey
    var logo = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: DS.Spacing.s) {
            if logo { AppMark(size: 36) }
            Text(title).font(Theme.displayFont)
            Spacer()
            trailing
        }
        .padding(.top, DS.Spacing.xs)
    }
}

struct RoundIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.headline)
            .foregroundStyle(Theme.accent)
            .frame(width: 38, height: 38)
            .background(Theme.card, in: Circle())
    }
}

/// Section title used inside scroll views.
struct SectionTitle: View {
    let text: LocalizedStringKey
    var trailing: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(text).font(Theme.titleFont)
            Spacer()
            if let trailing { Text(trailing).font(.subheadline).foregroundStyle(.secondary) }
        }
    }
}
