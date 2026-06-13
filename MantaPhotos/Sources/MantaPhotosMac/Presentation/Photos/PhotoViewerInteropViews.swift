import AppKit
import Photos
import PhotosUI
import SwiftUI

// MARK: - 架构说明（本文件是什么 / 为什么单独存在）
//
// 本文件收纳 `PhotoViewerView`（见 `PhotoViewerView.swift`）用到的所有
// **AppKit interop** 代码——即所有 `NSViewRepresentable` 包装类型和它们
// 背后的 `NSView`/`NSScrollView` 子类：
//   - `HostedOverlay`            叠加在图片上的工具栏宿主
//   - `ZoomableImageView`        静态图缩放/平移/双击/滑动手势
//   - `SwipeAwareScrollView`     上面那个视图背后的 `NSScrollView` 子类
//   - `LivePhotoPlayerView`      Live Photo 播放
//   - `ViewerKeyCommandsView`    查看器键盘快捷键（隐藏 NSView，处理 keyDown）
//
// 之所以从 `PhotoViewerView.swift` 拆出来独立成文件，是因为查看器的
// 「手势失效」「快捷键失效」「按钮位置错乱」这三类问题已经反复出现了 3 次，
// 每次都是因为有人在调整 SwiftUI 布局（`body`/工具栏/详情面板等）时，
// **顺手**改动到了下面这些 AppKit 视图，而没有意识到它们之间有一套独立、
// 脆弱的 hitTest / 第一响应者协议。拆成两个文件之后：
//   - `PhotoViewerView.swift`         只关心 SwiftUI 布局/状态/业务逻辑，
//     正常情况下完全不需要打开本文件。
//   - `PhotoViewerInteropViews.swift`（本文件）只关心 AppKit interop，
//     **任何改动前必须完整阅读下面每个类型的文档注释**，并对照
//     `MantaPhotos/照片查看器交互问题记录与修改指南.md` 里的检查清单。
//
// 这两个文件本质上仍是「同一个查看器」的两个切面，互相之间通过类型名引用
// （`HostedOverlay`/`ZoomableImageView`/`LivePhotoPlayerView`/
// `ViewerKeyCommandsView` 均为 `private`，仅限同一个 module/target 内的
// `PhotoViewerView.swift` 使用——Swift 的 `private` 在文件级别其实是
// `fileprivate` 语义，**如果以后要跨文件访问，需要把可见性提到
// `internal`**，目前两个文件都在同一个 target 内，`private` 仍然是
// file-scoped，所以这里全部改成同 target 内可见的最小可见性即可）。

/// 把 SwiftUI 内容包装为独立的 `NSHostingView` 子视图，用于查看器里叠在
/// `ZoomableImageView`（`NSScrollView`）之上的工具栏。
///
/// **背景（查看器按钮/手势/快捷键反复失效的问题史，请通读）**：
///
/// 1. 第一次：`viewerChrome` 是纯 SwiftUI 视图，直接作为
///    `ZStack { mediaContent; viewerChrome }` 的子视图。`mediaContent`
///    （`ZoomableImageView`，`NSViewRepresentable` 包装的真实 `NSScrollView`）
///    与 `viewerChrome` 大面积重叠。AppKit 的 `NSView.hitTest(_:)` 默认实现
///    **总是先检查真实子视图**，只有所有子视图都返回 `nil` 才回退到「自身
///    绘制内容」；纯 SwiftUI 的 `viewerChrome` 只是父 `NSHostingView` 自身
///    绘制的内容，天然排在 `NSScrollView` 子视图之后被测试——导致重叠区域
///    内的按钮点击 / 快捷键全部被 `NSScrollView` 截获。
///
/// 2. 第二次（`HostedOverlay` 的由来）：把 `viewerChrome`（包含上下两条
///    工具栏 + 中间一个 `Spacer()` 的 `VStack`）整体包成**一个**
///    `HostedOverlay`。但 `VStack` 带 `Spacer()` 是「flexible」的，SwiftUI
///    会把它在 ZStack 里撑满到与 `mediaContent` 同样大小——于是这个
///    `NSHostingView` 的 `frame` 覆盖了**整个查看器区域**，包括中间的图片
///    手势区。`NSHostingView` 对自身 `bounds` 内任意一点的默认 `hitTest`
///    返回 `self`（即使该点落在 SwiftUI 内容的空白/`Spacer` 区域），而不是
///    像文档曾经假设的那样穿透——于是这个「铺满全屏」的 `NSHostingView`
///    在 z-order 上盖住了 `NSScrollView`，**反而把图片区域的捏合缩放/拖拽
///    平移/双击缩放/双指滑动切图的鼠标与触控板事件全部截获**，按钮本身能点
///    但手势全部失效；同时由于点击图片区域时第一响应者落在这个空的
///    `NSHostingView` 上而非 `SwipeAwareScrollView`，无修饰键的
///    `.keyboardShortcut`（方向键/Space/字母键）也变得不可靠。
///
/// 3. 第三次（本次修复）：
///    - **手势**：不再用一个铺满全屏的 `HostedOverlay`。改为给
///      `viewerTopBar` 和 `viewerBottomBar` **各自**一个 `HostedOverlay`，
///      二者放进 `VStack(spacing: 0) { HostedOverlay{top}; Spacer(); HostedOverlay{bottom} }`。
///      `HostedOverlay{top}` / `HostedOverlay{bottom}` 内部都是「自然高度」
///      的 `HStack`（非 flexible），SwiftUI 只会给它们分配各自内容的高度——
///      因此对应的 `NSHostingView` 的 `frame` 只覆盖屏幕最上/最下的一条
///      工具栏「窄带」，中间大片图片区域**没有任何覆盖层 NSView**，
///      `NSScrollView` 的手势完全不受影响。
///    - **快捷键**：彻底不再依赖 `.keyboardShortcut` + 覆盖层 hit-test/
///      第一响应者的微妙交互，改用专门的 `ViewerKeyCommandsView`
///      （见其文档）直接处理 `keyDown`。
///    - **按钮定位**（第 4 次报告的问题，本次一并修复）：`viewerTopBar`/
///      `viewerBottomBar` 内部用 `Spacer()` 把按钮分别推到两端，但
///      `NSHostingView` 默认按内容在「无约束」环境下的理想尺寸报告
///      `intrinsicContentSize`，并不会自动撑满父 `VStack` 的横向空间——
///      于是 `Spacer()` 没有可撑的宽度，按钮全部挤在窄条左侧中间。修复：
///      在 `PhotoViewerView.swift` 的 `viewerOverlayBars` 里，给每个
///      `HostedOverlay{...}` **外面**加 `.frame(maxWidth: .infinity)`
///      （只设宽度、不设高度，高度仍由内容自然高度决定，不会盖住图片区）。
///
/// **预防再次破坏（修改本文件前必读）**：
///   - 任何叠加在 `ZoomableImageView`/`SwipeAwareScrollView` 之上、包含
///     按钮的 SwiftUI 控件，必须用 `HostedOverlay` 包装。
///   - `HostedOverlay` 包裹的内容**绝对不能**是 flexible/铺满整个 ZStack 的
///     容器（不能带 `Spacer()` 让自身撑满）——只能是「自然尺寸」贴边的窄条
///     （顶部栏/底部栏/单个按钮等）。`.frame(maxWidth: .infinity)` 这类
///     撑满修饰符只能加在 `HostedOverlay { ... }` **外面**（详见上文「按钮
///     定位」），不能加在 `content` 内部，否则会重新覆盖手势区域，重现
///     「手势失效」。
///   - 任何键盘快捷键改动，去 `ViewerKeyCommandsView` 改，不要在按钮上加
///     `.keyboardShortcut`。
struct HostedOverlay<Content: View>: NSViewRepresentable {
    var content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let hostingView = NSHostingView(rootView: content)
        // 默认背景不透明会挡住下层 `NSScrollView` 中的照片——
        // 必须显式透明，否则 `viewerChrome` 区域会出现一块不透明遮罩。
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        return hostingView
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.rootView = content
    }
}

/// 原生可缩放图片视图：基于 `NSScrollView` 的 `allowsMagnification`，
/// 免费获得与系统照片一致的触控板手势——
/// 捏合缩放、放大后双指拖拽 / 滚动平移、双击切换缩放；未放大时横向滑动切换上一/下一张。
struct ZoomableImageView: NSViewRepresentable {
    var image: NSImage
    var onNavigate: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SwipeAwareScrollView {
        let scrollView = SwipeAwareScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 6
        scrollView.onNavigate = onNavigate

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = image
        imageView.autoresizingMask = [.width, .height]
        imageView.frame = scrollView.bounds
        scrollView.documentView = imageView

        let doubleClick = NSClickGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleClick(_:))
        )
        doubleClick.numberOfClicksRequired = 2
        scrollView.addGestureRecognizer(doubleClick)

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        return scrollView
    }

    func updateNSView(_ scrollView: SwipeAwareScrollView, context: Context) {
        scrollView.onNavigate = onNavigate
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.magnification = 1
            context.coordinator.imageView?.frame = scrollView.bounds
        }
    }

    final class Coordinator {
        weak var scrollView: NSScrollView?
        weak var imageView: NSImageView?

        @MainActor @objc func handleDoubleClick(_ recognizer: NSClickGestureRecognizer) {
            guard let scrollView else { return }
            if scrollView.magnification > 1.01 {
                scrollView.magnification = 1
            } else {
                let point = recognizer.location(in: scrollView.documentView ?? scrollView)
                scrollView.setMagnification(2.5, centeredAt: point)
            }
        }
    }
}

/// 未放大时把横向双指滑动解释为「上一/下一张」，其余情况交给 `NSScrollView` 原生平移。
final class SwipeAwareScrollView: NSScrollView {
    var onNavigate: ((Int) -> Void)?
    private var swipeAccumulator: CGFloat = 0
    private var swipeFired = false

    /// 显式声明「不参与第一响应者」。
    ///
    /// 查看器的键盘快捷键由 `ViewerKeyCommandsView` 这个常驻的隐藏 `NSView`
    /// 统一处理（见其文档）。如果用户点击图片时 `NSScrollView` 抢走了第一
    /// 响应者，`ViewerKeyCommandsView` 就再收不到 `keyDown`，方向键/Space/
    /// 字母键快捷键会再次失效。本视图本身不需要键盘输入（缩放/平移/滑动都是
    /// 鼠标和触控板事件），因此返回 `false`，把第一响应者让给
    /// `ViewerKeyCommandsView`。
    override var acceptsFirstResponder: Bool { false }

    override func scrollWheel(with event: NSEvent) {
        let horizontalDominant = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5
        if magnification <= 1.01, horizontalDominant {
            if event.phase == .began {
                swipeAccumulator = 0
                swipeFired = false
            }
            swipeAccumulator += event.scrollingDeltaX
            if !swipeFired, abs(swipeAccumulator) >= 60 {
                onNavigate?(swipeAccumulator < 0 ? 1 : -1)
                swipeFired = true
            }
            if event.phase == .ended || event.momentumPhase == .ended {
                swipeAccumulator = 0
                swipeFired = false
            }
            return
        }
        super.scrollWheel(with: event)
    }
}

struct LivePhotoPlayerView: NSViewRepresentable {
    var livePhoto: PHLivePhoto
    @Binding var isPlaying: Bool

    func makeNSView(context: Context) -> PHLivePhotoView {
        let view = PHLivePhotoView()
        view.livePhoto = livePhoto
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PHLivePhotoView, context: Context) {
        if view.livePhoto != livePhoto {
            view.livePhoto = livePhoto
            context.coordinator.isPlaybackActive = false
        }

        if isPlaying, !context.coordinator.isPlaying {
            view.startPlayback(with: .full)
            context.coordinator.isPlaybackActive = true
        } else if !isPlaying, context.coordinator.isPlaying {
            view.stopPlayback()
            context.coordinator.isPlaybackActive = false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isPlaying: $isPlaying)
    }

    final class Coordinator: NSObject, PHLivePhotoViewDelegate {
        @Binding var playbackRequested: Bool
        var isPlaybackActive = false

        var isPlaying: Bool { isPlaybackActive }

        init(isPlaying: Binding<Bool>) {
            _playbackRequested = isPlaying
        }

        func livePhotoView(_ livePhotoView: PHLivePhotoView, didEndPlaybackWith playbackStyle: PHLivePhotoViewPlaybackStyle) {
            isPlaybackActive = false
            playbackRequested = false
        }
    }
}

/// 查看器键盘快捷键：专用的、不可见、不接收鼠标事件的 `NSView`，直接处理
/// `keyDown`——不再使用 SwiftUI 的 `.keyboardShortcut`。
///
/// **这是「快捷键反复失效」问题的根因修复**。`.keyboardShortcut(_, modifiers: [])`
/// （无修饰键的方向键/Space/字母键）依赖 SwiftUI 把对应 `KeyboardShortcut`
/// 注册到所在 `NSHostingView` 的 `performKeyEquivalent` 链上，而
/// `NSWindow` 调用 `performKeyEquivalent` 的遍历顺序、以及当前第一响应者
/// 是谁，都会随查看器视图层级（`HostedOverlay` 拆分、覆盖层增减等）的每次
/// 调整而变化——这正是本类 bug 反复出现三次的原因：**只要查看器的覆盖层
/// 结构变了，依附在 SwiftUI 按钮上的无修饰键快捷键就有失效风险**。
///
/// 改为本视图后，快捷键的可用性只依赖三件简单、稳定的事：
///   1. 本视图是否在视图树中（`viewDidMoveToWindow` 时设为第一响应者）；
///   2. 窗口是否真正成为 key window（`NSWindow.didBecomeKeyNotification`
///      时再抢一次第一响应者——见下方「首次打开延迟生效」修复）；
///   3. 第一响应者是否被其他视图抢走（`SwipeAwareScrollView` 已显式
///      `acceptsFirstResponder = false`，`detailPanel` 内没有可聚焦控件，
///      `updateNSView` 里也会自愈）。
///
/// **修改注意点**：
///   - 新增查看器快捷键，在 `KeyCommandView.keyDown` 里加 `case`，不要在
///     SwiftUI 按钮上加 `.keyboardShortcut`。
///   - 若查看器内新增需要键盘输入的控件（如文本框），需要在该控件获得焦点
///     期间临时让出第一响应者——目前查看器内没有这类控件。
///   - 本视图 `frame` 固定为 0x0 且 `hitTest` 总返回 `nil`，对鼠标/手势
///     零影响，可以放在 ZStack 任意位置。
struct ViewerKeyCommandsView: NSViewRepresentable {
    var onBack: () -> Void
    var onPrevious: () -> Void
    var onNext: () -> Void
    var onTogglePlayback: (() -> Void)?
    var onToggleTrash: () -> Void
    var onToggleFavorite: () -> Void
    var onDelete: () -> Void
    var onToggleInfo: () -> Void

    func makeNSView(context: Context) -> KeyCommandView {
        let view = KeyCommandView()
        view.handlers = handlers
        return view
    }

    func updateNSView(_ nsView: KeyCommandView, context: Context) {
        nsView.handlers = handlers
        // 自愈：如果第一响应者被其他视图抢走（例如用户点了详情栏里的按钮），
        // 在下一次视图更新时重新把第一响应者交还给本视图，确保快捷键持续可用。
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async { [weak nsView] in
                guard let nsView, let window = nsView.window else { return }
                if window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
            }
        }
    }

    private var handlers: KeyCommandView.Handlers {
        KeyCommandView.Handlers(
            onBack: onBack,
            onPrevious: onPrevious,
            onNext: onNext,
            onTogglePlayback: onTogglePlayback,
            onToggleTrash: onToggleTrash,
            onToggleFavorite: onToggleFavorite,
            onDelete: onDelete,
            onToggleInfo: onToggleInfo
        )
    }

    final class KeyCommandView: NSView {
        struct Handlers {
            var onBack: () -> Void
            var onPrevious: () -> Void
            var onNext: () -> Void
            var onTogglePlayback: (() -> Void)?
            var onToggleTrash: () -> Void
            var onToggleFavorite: () -> Void
            var onDelete: () -> Void
            var onToggleInfo: () -> Void
        }

        var handlers: Handlers?

        override var acceptsFirstResponder: Bool { true }

        // 不接收鼠标事件、不挡住任何手势——本视图只用于成为第一响应者以接收键盘事件。
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        /// **修复「查看器首次打开时快捷键/手势要过一会才生效」**：
        ///
        /// 查看器刚出现的那一帧，`window` 还没有成为 key window（呈现动画/
        /// 窗口焦点切换尚未完成），此时 `makeFirstResponder` 即使调用成功，
        /// AppKit 也暂时不会把按键事件投递给 `self`——直到 `NSWindow` 真正
        /// `becomeKey`。在那之前，`updateNSView` 里的「自愈」逻辑只有在
        /// SwiftUI 触发新一轮 body 求值（例如缩略图加载完成）时才会被调用，
        /// 所以表现为「过一会才生效」。
        ///
        /// 修复：除了 `viewDidMoveToWindow` 时立即尝试一次，还监听
        /// `NSWindow.didBecomeKeyNotification`，窗口真正变为 key window 的
        /// 那一刻再抢一次第一响应者——不依赖任何后续的 SwiftUI 状态变化。
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            guard let window else { return }
            window.makeFirstResponder(self)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleWindowDidBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            // 双重保险：即使 `window` 此刻已是 key window，SwiftUI 在同一次
            // 布局过程里也可能稍后把第一响应者设置成别的视图（例如它自己的
            // 根 `NSHostingView`）。下一个 runloop 再抢一次，覆盖这种情况。
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window, window.firstResponder !== self else { return }
                window.makeFirstResponder(self)
            }
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleWindowDidBecomeKey() {
            guard let window, window.firstResponder !== self else { return }
            window.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard let handlers else {
                super.keyDown(with: event)
                return
            }
            // 只处理无修饰键的按键；带 Cmd/Option/Control 的组合键交还系统
            // （菜单快捷键、窗口管理快捷键等），避免互相冲突。
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            guard modifiers.isEmpty else {
                super.keyDown(with: event)
                return
            }

            switch Int(event.keyCode) {
            case 53: // Escape
                handlers.onBack()
            case 123: // Left Arrow
                handlers.onPrevious()
            case 124: // Right Arrow
                handlers.onNext()
            case 49: // Space
                // 即使当前媒体不支持播放/暂停（`onTogglePlayback == nil`），也要
                // 吞掉 Space，避免触发系统提示音——等价于旧版里那个空操作的
                // 隐藏 Space 按钮。
                handlers.onTogglePlayback?()
            default:
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "t":
                    handlers.onToggleTrash()
                case "f":
                    handlers.onToggleFavorite()
                case "d":
                    handlers.onDelete()
                case "i":
                    handlers.onToggleInfo()
                default:
                    super.keyDown(with: event)
                }
            }
        }
    }
}
