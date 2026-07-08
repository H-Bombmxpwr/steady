import SwiftUI

/// Dark-first visual identity: deep slate surfaces, an emerald→cyan accent
/// gradient, rounded type, and soft cards instead of stock grouped lists.
enum Theme {
    static let background = Color(hex: 0x0E1116)
    static let surface    = Color(hex: 0x171C24)
    static let surface2   = Color(hex: 0x1F2630)
    static let accent     = Color(hex: 0x34D399)   // emerald
    static let accent2    = Color(hex: 0x22D3EE)   // cyan
    static let warn       = Color(hex: 0xFBBF24)   // amber
    static let danger     = Color(hex: 0xFB7185)   // rose
    static let textDim    = Color.white.opacity(0.55)

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var flame: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF97316), Color(hex: 0xFBBF24)],
                       startPoint: .bottom, endPoint: .top)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textDim)
                    .kerning(1.2)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.06))
                )
        )
    }
}

// MARK: - Ring

struct StatRing: View {
    let value: Double        // 0...1+
    let label: String
    let detail: String
    var overIsBad = false
    var size: CGFloat = 84

    private var over: Bool { overIsBad && value > 1.0 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Theme.surface2, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(1, value))
                    .stroke(over ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.gradient),
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(detail)
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(over ? Theme.danger : .white)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 10)
            }
            .frame(width: size, height: size)
            .animation(.easeOut(duration: 0.4), value: value)
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
        }
    }
}

// MARK: - Bar

struct GradientBar: View {
    let value: Double        // 0...1+
    var overIsBad = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surface2)
                Capsule()
                    .fill(overIsBad && value > 1 ? AnyShapeStyle(Theme.danger) : AnyShapeStyle(Theme.gradient))
                    .frame(width: max(8, geo.size.width * min(1, value)))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

// MARK: - Form styling helper

extension View {
    /// Shared dark styling for Form-based screens.
    func themedForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    func themedRoot() -> some View {
        self
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
            .fontDesign(.rounded)
    }
}
