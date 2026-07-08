import SwiftUI

// MARK: - User-selectable palette + appearance

enum ThemePalette: String, CaseIterable, Identifiable {
    case emerald, ocean, sunset, violet, rose

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var accents: (Color, Color) {
        switch self {
        case .emerald: return (Color(hex: 0x34D399), Color(hex: 0x22D3EE))
        case .ocean:   return (Color(hex: 0x38BDF8), Color(hex: 0x6366F1))
        case .sunset:  return (Color(hex: 0xFB923C), Color(hex: 0xF43F5E))
        case .violet:  return (Color(hex: 0xA78BFA), Color(hex: 0xEC4899))
        case .rose:    return (Color(hex: 0xFB7185), Color(hex: 0xFBBF24))
        }
    }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, dark, light
    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .dark: return .dark
        case .light: return .light
        }
    }
}

/// Visual identity. Accent palette and light/dark mode are user-configurable
/// (Settings → Appearance); surfaces adapt to the active color scheme.
enum Theme {
    static let paletteKey = "theme.palette"
    static let modeKey = "theme.mode"

    static var palette: ThemePalette {
        ThemePalette(rawValue: UserDefaults.standard.string(forKey: paletteKey) ?? "") ?? .emerald
    }

    static var mode: ThemeMode {
        ThemeMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? .dark
    }

    static var accent: Color { palette.accents.0 }
    static var accent2: Color { palette.accents.1 }

    static var gradient: LinearGradient {
        LinearGradient(colors: [accent, accent2], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var flame: LinearGradient {
        LinearGradient(colors: [Color(hex: 0xF97316), Color(hex: 0xFBBF24)],
                       startPoint: .bottom, endPoint: .top)
    }

    // Adaptive surfaces: deep slate in dark mode, soft neutrals in light.
    static let background = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x0E1116) : UIColor(hex: 0xF2F4F7)
    })
    static let surface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x171C24) : UIColor.white
    })
    static let surface2 = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(hex: 0x1F2630) : UIColor(hex: 0xE4E8EE)
    })

    static let warn = Color(hex: 0xF59E0B)
    static let danger = Color(hex: 0xE11D48)
    static let textDim = Color.primary.opacity(0.55)
    static let hairline = Color.primary.opacity(0.08)
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

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
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
                        .strokeBorder(Theme.hairline)
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
                    .foregroundStyle(over ? Theme.danger : .primary)
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
    /// Shared styling for Form-based screens.
    func themedForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }

    func themedRoot() -> some View {
        modifier(ThemedRoot())
    }
}

/// Applies tint, appearance mode, and rounded type; re-renders when the
/// user changes theme settings.
private struct ThemedRoot: ViewModifier {
    @AppStorage(Theme.paletteKey) private var palette = ThemePalette.emerald.rawValue
    @AppStorage(Theme.modeKey) private var mode = ThemeMode.dark.rawValue

    func body(content: Content) -> some View {
        content
            .tint((ThemePalette(rawValue: palette) ?? .emerald).accents.0)
            .preferredColorScheme((ThemeMode(rawValue: mode) ?? .dark).colorScheme)
            .fontDesign(.rounded)
    }
}
