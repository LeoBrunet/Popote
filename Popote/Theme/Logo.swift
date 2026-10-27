import SwiftUI

/// "Tomate" logo picked in UIStudio: a white tomato with a "p" and basil leaves on a tomato squircle.
/// The earlier "Marmite fumante" glyph is kept below (MarmiteGlyph).
struct AppMark: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(Theme.accent.gradient)
            TomateGlyph(ink: Theme.onAccent, accent: Theme.accent).frame(width: size * 0.62, height: size * 0.62)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Wavy vertical line, used for steam.
private struct Steam: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY + h * 0.5),
                   control1: CGPoint(x: rect.midX - w, y: rect.maxY - h * 0.15),
                   control2: CGPoint(x: rect.midX + w, y: rect.minY + h * 0.65))
        p.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                   control1: CGPoint(x: rect.midX - w, y: rect.minY + h * 0.35),
                   control2: CGPoint(x: rect.midX + w, y: rect.minY + h * 0.15))
        return p
    }
}

struct MarmiteGlyph: View {
    let ink: Color

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            VStack(spacing: s * 0.04) {
                HStack(spacing: s * 0.13) {
                    ForEach(0..<3) { i in
                        Steam()
                            .stroke(ink, style: StrokeStyle(lineWidth: s * 0.06, lineCap: .round))
                            .frame(width: s * 0.08, height: s * (i == 1 ? 0.30 : 0.24))
                    }
                }
                VStack(spacing: s * 0.03) {
                    Capsule().fill(ink).frame(width: s * 0.14, height: s * 0.07)          // knob
                    Capsule().fill(ink).frame(width: s * 0.86, height: s * 0.08)          // lid
                    UnevenRoundedRectangle(bottomLeadingRadius: s * 0.2, bottomTrailingRadius: s * 0.2)
                        .fill(ink)
                        .frame(width: s * 0.70, height: s * 0.34)                         // body
                        .overlay {
                            HStack {
                                Capsule().fill(ink).frame(width: s * 0.12, height: s * 0.06)
                                Spacer()
                                Capsule().fill(ink).frame(width: s * 0.12, height: s * 0.06)
                            }
                            .frame(width: s * 0.94)
                            .offset(y: -s * 0.08)
                        }
                }
            }
            .frame(width: s, height: geo.size.height)
        }
    }
}

struct TomateGlyph: View {
    let ink: Color
    let accent: Color

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width
            ZStack {
                Ellipse().fill(ink).frame(width: s * 0.9, height: s * 0.78).offset(y: s * 0.1)
                Text("p")
                    .font(.system(size: s * 0.5, weight: .black, design: .rounded))
                    .foregroundStyle(accent)
                    .offset(y: s * 0.06)
                // Leaves
                HStack(spacing: -s * 0.04) {
                    Ellipse().fill(Theme.herb).frame(width: s * 0.22, height: s * 0.1).rotationEffect(.degrees(-25))
                    Capsule().fill(Theme.herb).frame(width: s * 0.06, height: s * 0.18).offset(y: -s * 0.06)
                    Ellipse().fill(Theme.herb).frame(width: s * 0.22, height: s * 0.1).rotationEffect(.degrees(25))
                }
                .offset(y: -s * 0.3)
            }
            .frame(width: s, height: geo.size.height)
        }
    }
}
