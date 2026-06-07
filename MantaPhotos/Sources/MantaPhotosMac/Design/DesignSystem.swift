import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let control: CGFloat = 6
        static let panel: CGFloat = 8
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 252
        static let topBarHeight: CGFloat = 54
        static let bottomBarHeight: CGFloat = 36
    }

    enum Palette {
        static let scoreHigh = Color(red: 0.08, green: 0.55, blue: 0.32)
        static let scoreMedium = Color(red: 0.78, green: 0.50, blue: 0.10)
        static let scoreLow = Color(red: 0.74, green: 0.18, blue: 0.18)
        static let accent = Color.accentColor
    }
}
