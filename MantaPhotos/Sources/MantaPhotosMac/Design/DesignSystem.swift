import AppKit
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
        /// 0.85（而非纯黑 0.9+）：略微调低，让详情栏的 `.ultraThinMaterial`
        /// 液态玻璃在深色背景上仍能透出一点层次，不会呈现为「纯黑面板」。
        static let viewerBackdrop = Color.black.opacity(0.85)
    }

    enum Metrics {
        static let sidebarWidth: CGFloat = 252
        /// 顶部标签栏固定高度。集中常量 + `.frame(height:)` 强约束，
        /// 保证有无照片、各分区菜单切换时高度完全一致、不被内容撑高。
        static let topBarHeight: CGFloat = 48
        static let bottomBarHeight: CGFloat = 36
        /// 「特殊相册」横幅（相似照片结果 / 废片篓 / 已应用筛选）固定高度。
        /// 与 `topBarHeight` 同理：用固定高度强约束，避免无结果、长标题等场景把
        /// 菜单区域撑高（对应历史 bug：特殊筛选后无结果时菜单区域过高）。
        static let bannerHeight: CGFloat = 44
        /// 照片页悬浮工具栏固定高度（标题/计数、导入、评分菜单、缩放、角标、排序）。
        static let photosToolbarHeight: CGFloat = 58
    }

    enum Palette {
        static let scoreHigh = Color(red: 0.08, green: 0.55, blue: 0.32)
        static let scoreMedium = Color(red: 0.78, green: 0.50, blue: 0.10)
        static let scoreLow = Color(red: 0.74, green: 0.18, blue: 0.18)
        static let accent = Color.accentColor
    }
}

/// 液态玻璃按钮的悬浮反馈：贴近 macOS 工具栏「玻璃按钮」在鼠标悬浮时轻微点亮 + 放大的交互语言
/// （如系统照片 App 顶部工具栏）。不引入额外色彩，只叠加一层随外观自适应的 `primary` 透明遮罩。
private struct GlassHoverHighlight<S: Shape>: ViewModifier {
    let shape: S
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                // `allowsHitTesting(false)`：这层只是装饰性高光，不能拦截下层
                // 按钮/菜单的点击——否则会出现「悬浮有效果但点击无响应」的问题。
                shape.fill(Color.primary.opacity(isHovering ? 0.10 : 0))
                    .allowsHitTesting(false)
            }
            .scaleEffect(isHovering ? 1.04 : 1.0)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}

extension View {
    /// 为液态玻璃按钮 / 分段控件添加 hover 高亮 + 轻微放大反馈。
    func glassHoverHighlight<S: Shape>(in shape: S) -> some View {
        modifier(GlassHoverHighlight(shape: shape))
    }
}

/// 液态玻璃按钮的「按下」反馈：在 `glassHoverHighlight` 的悬浮高亮之外，
/// 补充按下瞬间的轻微缩小 + 加深一档的不透明遮罩，贴近系统照片 App 顶部/底部
/// 工具栏按钮按下时的「回弹」手感。
///
/// 仅做视觉层（缩放 + 透明度），不改变 `action` 的触发逻辑——
/// 套用本样式不会影响按钮原有功能。
struct PressableGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableGlassButtonStyle {
    /// 液态玻璃按钮的标准按下反馈样式。
    static var pressableGlass: PressableGlassButtonStyle { PressableGlassButtonStyle() }
}

/// 液态玻璃背板：基于 `NSVisualEffectView`，强制 `.withinWindow` 混合 + `.active` 状态。
///
/// **修复「从其他 App 切换回来时，玻璃背景先黑后透明」**：SwiftUI 系统材质
/// （`.ultraThinMaterial` / `.regularMaterial`）以及 `.glassEffect()` 默认按
/// `.behindWindow` 模式混合——需要 WindowServer 实时合成「窗口背后的桌面 /
/// 其他 App 内容」。本窗口被切到后台、再次变为前台的瞬间，这份跨进程合成尚未
/// 就绪，`NSVisualEffectView` 会先用纯黑占位，等首帧采样完成才淡入真正的玻璃
/// 效果——即抽屉、悬浮工具栏「先黑后透明」的闪烁。
///
/// 抽屉、悬浮工具栏等本就叠加在「本窗口自身已渲染好的内容」之上（同一
/// `ZStack`），改用 `.withinWindow` 混合只采样窗口自身图层，不依赖跨进程合成，
/// 因此没有这个延迟——`PhotoGridItem` 的评分角标（见 `PhotoGridView.swift`）
/// 一直用的就是这个方案，视觉效果与系统材质一致。
struct LiquidGlassBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

extension View {
    /// 用 `.withinWindow` 的 `NSVisualEffectView` 作为背景，替代 SwiftUI 系统
    /// `Material` / `.glassEffect()`（见 `LiquidGlassBackground`）。
    /// 抽屉、悬浮工具栏、按钮背板等浮层一律应使用此方法，避免应用切前台时的黑闪。
    func liquidGlassBackground<S: Shape>(
        material: NSVisualEffectView.Material = .hudWindow,
        in shape: S
    ) -> some View {
        background(LiquidGlassBackground(material: material).clipShape(shape))
    }

    /// 悬浮液态玻璃条：照片页顶部工具栏 / 横幅的统一外观——一条浮在照片墙上方的
    /// 圆角玻璃胶囊，而非贯穿全宽的不透明色块。滚动照片时透过玻璃可见下层内容，
    /// 不会出现遮挡视野的「黑条」，把更多面积留给照片本身。
    func floatingGlassBar() -> some View {
        self
            .liquidGlassBackground(material: .hudWindow, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay, style: .continuous)
                    .strokeBorder(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 4)
    }

    /// 独立悬浮液态玻璃胶囊：贴近系统照片 App 顶部工具栏「多颗独立胶囊/圆形按钮、
    /// 组间留白」的外观——每个功能分组各自一颗完全圆角的胶囊，而不是合并成
    /// 贯穿整行的长条（那是 `floatingGlassBar()` 的用途，留给页面级横幅）。
    func floatingGlassCapsule() -> some View {
        self
            .liquidGlassBackground(material: .hudWindow, in: Capsule())
            .overlay {
                Capsule().strokeBorder(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
    }

    /// 独立悬浮液态玻璃圆形：纯图标按钮，贴近系统照片 App 的 info / 分享 / 收藏等
    /// 圆形按钮。
    func floatingGlassCircle() -> some View {
        self
            .liquidGlassBackground(material: .hudWindow, in: Circle())
            .overlay {
                Circle().strokeBorder(DesignSystem.Glass.hairline, lineWidth: DesignSystem.Glass.hairlineWidth)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 3)
    }
}

/// 双滑块区间选择器。
///
/// 用于替代「大于 / 小于」运算符式的分数筛选：两端把手分别对应区间下界与上界，
/// 中段以系统强调色高亮，直观呈现当前筛选的分数区间。
/// 视觉语言贴近 macOS 原生 `Slider`（细凹槽 + 圆形把手 + 投影），
/// 拖动时切换为「张开的手」光标，符合系统级控件的交互反馈。
struct RangeSliderView: View {
    @Binding var lowerValue: Double
    @Binding var upperValue: Double
    var bounds: ClosedRange<Double> = 0...100
    var step: Double = 1

    private let thumbDiameter: CGFloat = 16
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let usableWidth = max(0, geometry.size.width - thumbDiameter)
            let lowerX = thumbDiameter / 2 + usableWidth * fraction(of: lowerValue)
            let upperX = thumbDiameter / 2 + usableWidth * fraction(of: upperValue)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(DesignSystem.Glass.activeTint)
                    .frame(width: max(0, upperX - lowerX), height: trackHeight)
                    .offset(x: lowerX)

                thumb(value: lowerValue, label: "Minimum score")
                    .position(x: lowerX, y: geometry.size.height / 2)
                    .gesture(dragGesture(usableWidth: usableWidth, isLower: true))

                thumb(value: upperValue, label: "Maximum score")
                    .position(x: upperX, y: geometry.size.height / 2)
                    .gesture(dragGesture(usableWidth: usableWidth, isLower: false))
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: thumbDiameter + 6)
    }

    private func fraction(of value: Double) -> Double {
        guard bounds.upperBound > bounds.lowerBound else { return 0 }
        return (value - bounds.lowerBound) / (bounds.upperBound - bounds.lowerBound)
    }

    private func value(at x: CGFloat, usableWidth: CGFloat) -> Double {
        guard usableWidth > 0 else { return bounds.lowerBound }
        let fraction = min(1, max(0, (x - thumbDiameter / 2) / usableWidth))
        let raw = bounds.lowerBound + fraction * (bounds.upperBound - bounds.lowerBound)
        return (raw / step).rounded() * step
    }

    private func dragGesture(usableWidth: CGFloat, isLower: Bool) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                NSCursor.closedHand.set()
                let newValue = value(at: drag.location.x, usableWidth: usableWidth)
                if isLower {
                    lowerValue = min(newValue, upperValue)
                } else {
                    upperValue = max(newValue, lowerValue)
                }
            }
            .onEnded { _ in
                NSCursor.openHand.set()
            }
    }

    private func thumb(value: Double, label: String) -> some View {
        Circle()
            .fill(.white)
            .frame(width: thumbDiameter, height: thumbDiameter)
            .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text("\(Int(value.rounded()))"))
            .onHover { hovering in
                if hovering {
                    NSCursor.openHand.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
    }
}
