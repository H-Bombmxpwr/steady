import SwiftUI
import UIKit
import Observation
import WidgetKit

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

/// A selectable app icon: one of the five palettes in either the light
/// (color background, white line) or dark (black background, colored line)
/// style. Both styles of every palette ship as fixed, single-appearance
/// alternate icons, so any of them can be chosen at any time regardless of
/// the in-app theme or the system's light/dark setting. The empty selection
/// (`nil` name) is the primary icon, which follows the system appearance.
struct AppIconOption: Identifiable, Equatable {
    let palette: ThemePalette
    let dark: Bool

    /// Alternate-icon asset name, e.g. "Icon-Ocean-Dark". Must match the
    /// .appiconset names and ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES.
    var assetName: String { "Icon-\(palette.label)-\(dark ? "Dark" : "Light")" }
    var id: String { assetName }

    /// Every palette in both styles, grouped palette-by-palette.
    static let all: [AppIconOption] = ThemePalette.allCases.flatMap {
        [AppIconOption(palette: $0, dark: false), AppIconOption(palette: $0, dark: true)]
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

/// Observable theme state. Views that read `Theme.accent`/`Theme.gradient`
/// during body evaluation register a dependency and re-render live when the
/// user changes the palette or mode — no restart, sheets included.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    var palette: ThemePalette {
        didSet {
            UserDefaults.standard.set(palette.rawValue, forKey: Theme.paletteKey)
            Self.mirrorToWidgets(palette)
        }
    }
    var mode: ThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Theme.modeKey) }
    }

    private init() {
        palette = ThemePalette(rawValue: UserDefaults.standard.string(forKey: Theme.paletteKey) ?? "") ?? .emerald
        mode = ThemeMode(rawValue: UserDefaults.standard.string(forKey: Theme.modeKey) ?? "") ?? .dark
        Self.mirrorToWidgets(palette)
    }

    /// Widgets run in their own process and can't see the app's defaults —
    /// mirror the palette into the App Group and refresh their timelines so
    /// accents match the in-app theme.
    private static func mirrorToWidgets(_ palette: ThemePalette) {
        UserDefaults(suiteName: appGroupID)?.set(palette.rawValue, forKey: Theme.paletteKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Visual identity. Accent palette and light/dark mode are user-configurable
/// (Settings → Appearance); surfaces adapt to the active color scheme.
enum Theme {
    static let paletteKey = "theme.palette"
    static let modeKey = "theme.mode"

    static var palette: ThemePalette { ThemeStore.shared.palette }
    static var mode: ThemeMode { ThemeStore.shared.mode }

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

// MARK: - Section identity

/// Fixed per-domain hues so screens aren't wall-to-wall theme accent —
/// water is always sky, alcohol always amber, and so on.
extension Theme {
    static let waterTint = Color(hex: 0x38BDF8)     // sky
    static let foodTint = Color(hex: 0xFB923C)      // tangerine
    static let weightTint = Color(hex: 0xA78BFA)    // violet
    static let alcoholTint = Color(hex: 0xF59E0B)   // amber
    static let supplementTint = Color(hex: 0x2DD4BF) // teal
    static let workoutTint = Color(hex: 0xF43F5E)   // raspberry
    static let photoTint = Color(hex: 0xEC4899)     // pink
    static let sleepTint = Color(hex: 0x818CF8)     // periwinkle
}

/// Each meal gets its own hue for chips, rows, and charts.
extension Meal {
    var color: Color {
        switch self {
        case .breakfast: return Color(hex: 0xFBBF24)      // sunrise gold
        case .morningSnack: return Color(hex: 0x34D399)   // mint
        case .lunch: return Color(hex: 0xFB923C)          // midday orange
        case .afternoonSnack: return Color(hex: 0x2DD4BF) // teal
        case .dinner: return Color(hex: 0x818CF8)         // dusk indigo
        case .dessert: return Color(hex: 0xEC4899)        // pink
        }
    }
}

/// Small icon chip — gives plain form rows and headers some character
/// without touching layout or behavior. Tint it per domain; falls back
/// to the theme gradient.
struct SectionIcon: View {
    let systemImage: String
    var size: CGFloat = 26
    var tint: Color? = nil

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                    .fill(tint.map {
                        AnyShapeStyle(LinearGradient(colors: [$0, $0.opacity(0.65)],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                    } ?? AnyShapeStyle(Theme.gradient))
            )
    }
}

/// Form section header with an icon chip and natural-case title.
struct SectionHeader: View {
    let icon: String
    let title: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            SectionIcon(systemImage: icon, size: 20, tint: tint)
            Text(title)
                .font(.footnote.bold())
                .foregroundStyle(.primary.opacity(0.8))
        }
        .textCase(nil)
        .padding(.bottom, 2)
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var title: String? = nil
    var icon: String? = nil
    var tint: Color? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 7) {
                    if let icon {
                        SectionIcon(systemImage: icon, size: 20, tint: tint)
                    }
                    Text(title.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textDim)
                        .kerning(1.2)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                // A faint lit-from-above wash in the card's own hue — depth
                // and color instead of a flat fill.
                .overlay(
                    LinearGradient(colors: [(tint ?? Theme.accent).opacity(0.07), .clear],
                                   startPoint: .top, endPoint: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(tint?.opacity(0.22) ?? Theme.hairline)
                )
                // Layered shadow: a soft ambient one to ground it, plus a
                // colored glow in the tint for that premium floating feel.
                .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                .shadow(color: (tint ?? Theme.accent).opacity(0.16), radius: 18, y: 9)
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
    var tint: Color? = nil   // per-metric hue; theme gradient when nil

    private var over: Bool { overIsBad && value > 1.0 }

    private var ringStyle: AnyShapeStyle {
        if over { return AnyShapeStyle(Theme.danger) }
        if let tint {
            return AnyShapeStyle(LinearGradient(colors: [tint, tint.opacity(0.55)],
                                                startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(Theme.gradient)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Theme.surface2, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: min(1, value))
                    .stroke(ringStyle,
                            style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(detail)
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundStyle(over ? Theme.danger : .primary)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 10)
            }
            .frame(width: size, height: size)
            .animation(.spring(response: 0.55, dampingFraction: 0.7), value: value)
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
        .animation(.spring(response: 0.5, dampingFraction: 0.75), value: value)
    }
}

// MARK: - Form styling helper

extension View {
    /// Shared styling for Form-based screens: base surface plus a breath of
    /// brand accent at the top — the app's signature backdrop.
    func themedForm() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(brandWash())
    }

    /// Scroll-screen version of the same backdrop.
    func brandBackground() -> some View {
        background(brandWash())
    }

    private func brandWash() -> some View {
        ZStack {
            Theme.background
            LinearGradient(colors: [Theme.accent.opacity(0.13),
                                    Theme.accent2.opacity(0.04),
                                    .clear],
                           startPoint: .top,
                           endPoint: UnitPoint(x: 0.5, y: 0.45))
        }
        .ignoresSafeArea()
    }

    func themedRoot() -> some View {
        modifier(ThemedRoot())
    }
}

/// Applies tint, appearance mode, and rounded type; re-renders when the
/// user changes theme settings. Sheets don't inherit `preferredColorScheme`
/// from the presenting view, so apply this to every sheet root too.
private struct ThemedRoot: ViewModifier {
    private let store = ThemeStore.shared

    func body(content: Content) -> some View {
        content
            .tint(store.palette.accents.0)
            .preferredColorScheme(store.mode.colorScheme)
            .fontDesign(.rounded)
    }
}

// MARK: - Keyboard helper

extension View {
    /// A "Done" button above the keyboard so number/text fields can always
    /// be dismissed. Apply once per Form/List that has input fields.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

// MARK: - Haptics

/// Thin wrapper over the feedback generators so taps and confirmations feel
/// physical instead of silent. Cheap to call; the OS coalesces rapid hits.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}

// MARK: - Button styles (spring press + haptic)

/// A subtle spring scale-down with a light haptic on press — keeps the
/// button's own look, just adds the tactile "give." Use anywhere:
/// `.buttonStyle(.pressable)`.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// A prominent call-to-action: accent (or tinted) gradient fill, white bold
/// label, and a soft colored shadow that tightens as the button presses in.
/// `.buttonStyle(.primaryAction)` or `.buttonStyle(.primaryAction(tint:))`.
struct PrimaryActionButtonStyle: ButtonStyle {
    var tint: Color? = nil

    private var fill: LinearGradient {
        if let tint {
            return LinearGradient(colors: [tint, tint.opacity(0.72)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        return Theme.gradient
    }

    func makeBody(configuration: Configuration) -> some View {
        let glow = tint ?? Theme.accent
        return configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(fill))
            .shadow(color: glow.opacity(configuration.isPressed ? 0.18 : 0.40),
                    radius: configuration.isPressed ? 5 : 14,
                    y: configuration.isPressed ? 2 : 7)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tap() }
            }
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { PrimaryActionButtonStyle() }
    static func primaryAction(tint: Color) -> PrimaryActionButtonStyle {
        PrimaryActionButtonStyle(tint: tint)
    }
}
