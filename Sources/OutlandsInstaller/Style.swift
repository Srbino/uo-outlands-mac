import AppKit
import SwiftUI

/// Colours adapt to Light and Dark appearance. Teal marks the primary action, amber risky
/// maintenance and red destructive actions.
enum Palette {
    static let accent = dynamic(dark: 0x2DD4BF, light: 0x0F766E)
    static let onAccent = dynamic(dark: 0x062420, light: 0xFFFFFF)
    static let window = dynamic(dark: 0x16191D, light: 0xF4F5F7)
    static let sidebar = dynamic(dark: 0x101316, light: 0xE9ECEF)
    static let statusBar = dynamic(dark: 0x13161A, light: 0xECEFF1)
    static let card = dynamic(dark: 0x1C2025, light: 0xFFFFFF)
    static let inset = dynamic(dark: 0x22272C, light: 0xF1F3F5)
    static let control = dynamic(dark: 0x252A30, light: 0xFFFFFF)
    static let border = dynamic(dark: 0x2A3036, light: 0xD9DEE3)
    static let warning = dynamic(dark: 0xF5B041, light: 0xB45309)
    static let danger = dynamic(dark: 0xF87171, light: 0xDC2626)
    static let neutral = dynamic(dark: 0x5B646D, light: 0x9AA4AD)

    private static func dynamic(dark: Int, light: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        })
    }
    private static func rgb(_ value: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
}

// MARK: Buttons

/// Custom styles keep their colours in inactive windows, unlike `.borderedProminent`.
struct ActionButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, warning, danger }
    var kind: Kind = .secondary
    var large = false
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, kind: kind, large: large, small: small)
    }
    private struct StyledBody: View {
        let configuration: Configuration
        let kind: Kind
        let large: Bool
        let small: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.isFocused) private var focused
        @Environment(\.colorSchemeContrast) private var contrast
        @State private var hovering = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: large ? 9 : small ? 6 : 7)
            configuration.label
                .font(.system(size: large ? 14 : small ? 12 : 13, weight: kind == .primary ? .semibold : .medium))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, large ? 20 : small ? 10 : 14)
                .frame(height: large ? 40 : small ? 26 : 30)
                .foregroundStyle(foreground)
                .background(background, in: shape)
                .overlay(shape.strokeBorder(focused ? Palette.accent : contrast == .increased ? .secondary : stroke, lineWidth: focused ? 3 : contrast == .increased ? 2 : 1))
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hovering = $0 }
        }
        private var foreground: Color {
            switch kind {
            case .primary: return Palette.onAccent
            case .secondary: return .primary
            case .warning: return Palette.warning
            case .danger: return Palette.danger
            }
        }
        private var background: Color {
            let active = enabled && (hovering || configuration.isPressed)
            switch kind {
            case .primary: return Palette.accent.opacity(configuration.isPressed ? 0.8 : active ? 0.9 : 1)
            case .secondary: return active ? Palette.inset : Palette.control
            case .warning: return Palette.warning.opacity(active ? 0.1 : 0)
            case .danger: return Palette.danger.opacity(active ? 0.1 : 0)
            }
        }
        private var stroke: Color {
            switch kind {
            case .primary: return .clear
            case .secondary: return Palette.border
            case .warning: return Palette.warning.opacity(0.5)
            case .danger: return Palette.danger.opacity(0.5)
            }
        }
    }
}

extension ButtonStyle where Self == ActionButtonStyle {
    static var action: ActionButtonStyle { ActionButtonStyle() }
    static func action(_ kind: ActionButtonStyle.Kind = .secondary, large: Bool = false, small: Bool = false) -> ActionButtonStyle {
        ActionButtonStyle(kind: kind, large: large, small: small)
    }
}

/// Text-only action, for secondary navigation such as "Report a problem…".
struct LinkButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    var small = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(small ? .caption.weight(.medium) : .callout.weight(.medium)).foregroundStyle(Palette.accent)
            .opacity(configuration.isPressed ? 0.7 : 1).contentShape(Rectangle())
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(focused ? Palette.accent : .clear, lineWidth: 3))
    }
}

/// Larger tile, used for Finder shortcuts.
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Tile(configuration: configuration) }
    private struct Tile: View {
        let configuration: Configuration
        @State private var hovering = false
        @Environment(\.isFocused) private var focused
        @Environment(\.colorSchemeContrast) private var contrast
        var body: some View {
            configuration.label
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(hovering || configuration.isPressed ? Palette.control : Palette.inset, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(focused ? Palette.accent : contrast == .increased ? .secondary : Palette.border, lineWidth: focused ? 3 : contrast == .increased ? 2 : 1))
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

// MARK: Building blocks

struct Card<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 18
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(contrast == .increased ? .secondary : Palette.border, lineWidth: contrast == .increased ? 2 : 1))
    }
}

/// Tinted banner for warnings, reminders and ready states.
struct Notice<Content: View>: View {
    let color: Color
    @ViewBuilder let content: Content
    var body: some View {
        HStack(alignment: .center, spacing: 12) { content }
            .font(.callout)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.3)))
    }
}

struct StatusDot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true) }
}

struct Badge: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.caption.weight(.semibold)).lineLimit(1)
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.13), in: Capsule())
    }
}

struct InfoChip: View {
    let systemImage: String
    let text: String
    var body: some View {
        Label(text, systemImage: systemImage).font(.caption)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Palette.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border))
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    var lead: String?
    @ViewBuilder var trailing: Trailing
    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("UO OUTLANDS").font(.caption.weight(.semibold)).tracking(2.5).foregroundStyle(Palette.accent)
                .accessibilityHidden(true)
            Text(title).font(.system(size: 26, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let lead { Text(lead).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .bottom, spacing: 16) {
                heading.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                HStack(spacing: 8) { trailing }.fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 12) {
                heading
                HStack(spacing: 8) { trailing }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, lead: String? = nil) { self.init(title: title, lead: lead) { EmptyView() } }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption.weight(.semibold)).tracking(0.8).foregroundStyle(.secondary)
            .padding(.leading, 4).padding(.bottom, -6).accessibilityAddTraits(.isHeader)
    }
}

/// Title and explanation on the left, one action on the right.
struct ActionRow<Action: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var action: Action
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            action
        }.padding(.vertical, 12)
    }
}


struct NavigationButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Palette.accent : .clear, lineWidth: 3))
    }
}
