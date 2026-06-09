import SwiftUI

/// 集中式设计令牌。
///
/// 原则（见《Mac 应用实现方案》5.6 主题设计）：
/// **设计令牌集中在 `DesignSystem`，不要在页面里散落颜色常量。**
/// 液态玻璃观感统一由系统 `Material` + 这里的少量令牌驱动，
/// 不在各视图里手写品牌渐变、黑色遮罩与魔法圆角。
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
        /// 胶囊化小控件 / 段控背板。
        static let chip: CGFloat = 10
        /// 卡片、输入框等中等表面。
        static let card: CGFloat = 12
        /// 侧栏、浮层等大型玻璃表面。
        static let overlay: CGFloat = 18
    }

    /// 液态玻璃专用令牌：描边、遮罩、强调态。
    enum Glass {
        /// 玻璃表面的细发丝描边，统一所有浮层/侧栏/搜索条的边缘。
        static let hairline = Color.white.opacity(0.18)
        static let hairlineWidth: CGFloat = 0.5

        /// 选中态统一使用系统强调色，贴近 macOS 原生 source list / 工具栏选择语义，
        /// 而不是让每个 active 状态都像独立品牌按钮（见重构清单 P2）。
        static let activeTint = Color.accentColor

        /// 浮层背后的遮罩：刻意更轻，避免把玻璃压暗（见重构清单 P3）。
        static let scrimLight = Color.black.opacity(0.12)
        static let scrimDark = Color.black.opacity(0.22)

        /// 查看器整屏底色：深而不死黑，给玻璃 chrome 留出层次（见重构清单 P4）。
        static let viewerBackdrop = Color.black.opacity(0.9)

        /// 保留的「唯一」品牌渐变，仅用于少数信号性强调态（如角标指标切换），
        /// 不再铺满所有选中态。
        static let brandGradient = LinearGradient(
            colors: [
                Color(red: 0.37, green: 0.36, blue: 0.90),
                Color(red: 0.75, green: 0.35, blue: 0.95)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
