import SwiftUI

extension Double {
    /// "2 840" (rounded, grouped).
    var kcalText: String { Int(rounded()).formatted() }
    /// "+850" / "−150".
    var signedKcal: String { "\(self < 0 ? "−" : "+")\(Int(abs(rounded())).formatted())" }
}

/// Journal card: what kind of day it is, today's target and why (« Carte explicative »).
struct DayTargetCard: View {
    let plan: DayPlan

    private var title: String {
        let kind = switch plan.kind {
        case .rest: String(localized: "Rest day")
        case .easy: String(localized: "Easy day")
        case .key: String(localized: "Key session")
        case .long: String(localized: "Long day")
        }
        return "\(kind): \(plan.kcal.kcalText) kcal"
    }

    private var subtitle: String {
        guard let first = plan.trainings.first else {
            return plan.fromHealth ? String(localized: "Resting + everyday movement from Apple Health")
                                   : String(localized: "Base target from Settings")
        }
        let names = plan.trainings.map(\.title).joined(separator: " + ")
        return first.real ? String(localized: "\(names) · recorded") : String(localized: "\(names) · planned in Coach")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.s) {
                Image(systemName: plan.trainings.first?.icon ?? "bed.double.fill")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(plan.kind == .rest ? Color.gray : plan.kind.color, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            HStack(spacing: 6) {
                if plan.training > 0 { pill(String(localized: "\(plan.training.signedKcal) training"), plan.kind.color) }
                if plan.adjust != 0 { pill(String(localized: "\(plan.adjust.signedKcal) goal"), Theme.accent) }
                pill(String(localized: "\(Int(plan.carbs)) g carbs"), Theme.carbs)
            }
        }
        .card(padding: DS.Spacing.s)
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Seven bars, one per day: height = target, colour = kind of day, today outlined.
struct WeekStrip: View {
    let week: [DayPlan]
    var selected: Date? = nil

    var body: some View {
        let maxKcal = week.map(\.kcal).max() ?? 1
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(week) { day in
                let highlighted = selected.map { Calendar.current.isDate($0, inSameDayAs: day.date) } ?? day.isToday
                VStack(spacing: 4) {
                    Text((day.kcal / 1000).formatted(.number.precision(.fractionLength(1))))
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .foregroundStyle(highlighted ? Color.primary : .secondary)
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(barColor(day).opacity(highlighted ? 1 : 0.55))
                        .frame(height: max(90 * day.kcal / maxKcal, 8))
                        .overlay {
                            if highlighted { RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.primary, lineWidth: 1.5) }
                        }
                    Image(systemName: day.trainings.first?.icon ?? "bed.double.fill").font(.system(size: 11)).foregroundStyle(barColor(day))
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2.weight(highlighted ? .bold : .regular))
                        .foregroundStyle(highlighted ? Color.primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Daily targets this week"))
    }

    private func barColor(_ day: DayPlan) -> Color { day.kind == .rest ? .gray : day.kind.color }
}

/// Shown on the Journal while there's no Coach plan: open Coach (installed) or install it, to plan each day from the sessions.
struct CoachInstallTile: View {
    var onDismiss: () -> Void
    @Environment(\.openURL) private var openURL

    private static let coachURL = URL(string: "coach://")!
    private var installed: Bool { UIApplication.shared.canOpenURL(Self.coachURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(alignment: .top, spacing: DS.Spacing.s) {
                Image(systemName: "figure.run")
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(CoachBadge.orange, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(installed ? "Share your Coach plan" : "Plan each day from your training").font(.subheadline.weight(.semibold))
                    Text(installed
                         ? "Open Coach once: it shares your sessions with Popote, and each day's target follows them."
                         : "With the Coach app, each day's target and carbs follow your planned sessions: more on long or hard days, less on rest days.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Hide")
            }
            if installed {
                Button { openURL(Self.coachURL) } label: { Label("Open Coach", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Label("Install the Coach app on this iPhone, then open it once.", systemImage: "arrow.down.app")
                    .font(.caption.weight(.semibold)).foregroundStyle(CoachBadge.orange)
            }
        }
        .card(padding: DS.Spacing.s)
    }
}
