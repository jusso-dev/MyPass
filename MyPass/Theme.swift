import SwiftUI
import UIKit

// MARK: - Color Palette

extension Color {
    /// MyPass brand colors — warm, calming palette with dark mode support
    enum mp {
        static let sky = Color(red: 0.53, green: 0.81, blue: 0.92)       // #87CEEB
        static let skyLight = Color(red: 0.69, green: 0.88, blue: 0.96)  // #B0E0F6

        /// Faint background — light: pale blue, dark: near-black with blue tint
        static let skyFaint = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.10, green: 0.12, blue: 0.16, alpha: 1)
                : UIColor(red: 0.91, green: 0.96, blue: 0.99, alpha: 1)
        })

        static let ocean = Color(red: 0.25, green: 0.61, blue: 0.76)     // #409CC2
        static let deepBlue = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.55, green: 0.78, blue: 0.90, alpha: 1)
                : UIColor(red: 0.16, green: 0.42, blue: 0.56, alpha: 1)
        })

        /// Warm gray background — adapts to system grouped background in dark mode
        static let warmGray = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1)
        })

        /// Card/section surface — light: near-white, dark: elevated surface
        static let softWhite = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.secondarySystemGroupedBackground
                : UIColor(red: 0.98, green: 0.99, blue: 1.0, alpha: 1)
        })

        static let trusted = Color(red: 0.30, green: 0.70, blue: 0.50)
        static let editor = Color(red: 0.40, green: 0.50, blue: 0.85)
        static let temporary = Color.orange
        static let readonly = Color(red: 0.53, green: 0.81, blue: 0.92)
    }
}

extension ShapeStyle where Self == Color {
    static var mpSky: Color { Color.mp.sky }
    static var mpOcean: Color { Color.mp.ocean }
}

// MARK: - Reusable View Modifiers

struct CardSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.mp.softWhite)
            .clipShape(.rect(cornerRadius: 14))
            .shadow(color: Color.mp.ocean.opacity(0.08), radius: 6, y: 2)
    }
}

extension View {
    func cardSectionStyle() -> some View {
        modifier(CardSectionStyle())
    }
}

// MARK: - Role Helpers

func roleColor(for role: String) -> Color {
    switch role {
    case "trusted": return Color.mp.trusted
    case "editor": return Color.mp.editor
    case "temporary": return Color.mp.temporary
    case "readonly": return Color.mp.readonly
    default: return .secondary
    }
}

/// User-friendly display name for a role.
func roleDisplayName(for role: String) -> String {
    switch role {
    case "editor": return "Can Edit"
    case "trusted": return "Full Access"
    case "temporary": return "Temporary Access"
    case "readonly": return "View Only"
    default: return role.capitalized
    }
}

// MARK: - Role Badge

struct RoleBadge: View {
    let role: String

    var body: some View {
        Text(roleDisplayName(for: role))
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(roleColor(for: role).opacity(0.15))
            .foregroundStyle(roleColor(for: role))
            .clipShape(Capsule())
    }
}
