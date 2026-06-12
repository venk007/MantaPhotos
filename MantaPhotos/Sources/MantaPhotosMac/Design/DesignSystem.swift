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
    ///
    /// material-first：浮层 chrome 一律用系统 `Material`，自动跟随 macOS 27「半透明度」
    /// 滑块与浅/深色、系统强调色。这里只保留**随外观自适应**的少量装饰令牌，不放固定颜色的
    /// 自绘 chrome。未来改用 `.glassEffect()`（macOS 26+）只需在此与各 `.background` 调用点替换。
    enum Glass {
        /// 发丝描边用 `primary` 透明度而非固定白：浅色 / 低透明玻璃上固定白会发灰，且不跟随半透明度滑块。
        static let hairline = Color.primary.opacity(0.12)
        static let hairlineWidth: CGFloat = 0.5

        /// 选中态统一使用系统强调色（跟随用户的系统强调色设置），不使用任何自绘渐变，
        /// 贴近 macOS 原生 source list / 工具栏选择语义。
        static let activeTint = Color.accentColor

        /// 浮层背后的遮罩：模态变暗层，与玻璃浓淡无关，刻意保持克制（见重构清单 P3）。
        static let scrimLight = Color.black.opacity(0.12)
        static let scrimDark = Color.black.opacity(0.22)

        /// 查看器整屏底色：照片置于深底之上（系统照片查看器同理），属内容呈现而非 chrome。
        static let viewerBackdrop = Color.black.opacity(0.9)
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 252
        /// 顶部标签栏固定高度。集中常量 + `.frame(height:)` 强约束，
        /// 保证有无照片、各分区菜单切换时高度完全一致、不被内容撑高。
        static let topBarHeight: CGFloat = 48
        static let bottomBarHeight: CGFloat = 36
    }

    enum Palette {
        static let scoreHigh = Color(red: 0.08, green: 0.55, blue: 0.32)
        static let scoreMedium = Color(red: 0.78, green: 0.50, blue: 0.10)
        static let scoreLow = Color(red: 0.74, green: 0.18, blue: 0.18)
        static let accent = Color.accentColor
    }
}
