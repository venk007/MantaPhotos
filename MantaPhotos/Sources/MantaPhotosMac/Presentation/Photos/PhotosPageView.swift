import SwiftUI

struct PhotosPageView: View {
    @Environment(AppState.self) private var appState

    // 年/月滚动导航状态
    @State private var dateSections: [GridDateSection] = []
    @State private var currentVisibleDate: Date?
    @State private var scrubberActive = false
    @State private var scrollToIndex: Int?
    @State private var scrubberHideTask: Task<Void, Never>?
    @State private var showEmptyTrashConfirm = false

    private var trashActionBar: some View {
        SpecialAlbumBannerView(icon: "trash", title: appState.localized("App Trash")) {
            Button {
                appState.library.restoreAllTrashed()
            } label: {
                Label("全部恢复", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.pressableGlass)
            .glassHoverHighlight(in: Capsule())
            Button(role: .destructive) {
                showEmptyTrashConfirm = true
            } label: {
                Label("清空（永久删除）", systemImage: "trash")
            }
            .buttonStyle(.pressableGlass)
            .glassHoverHighlight(in: Capsule())
        }
    }

    private var similarModeBar: some View {
        SpecialAlbumBannerView(icon: "rectangle.on.rectangle.angled", title: appState.localized("Similar Photos Results")) {
            Button {
                appState.library.exitSimilarMode()
            } label: {
                Label(appState.localized("Clear"), systemImage: "xmark")
            }
            .buttonStyle(.pressableGlass)
            .glassHoverHighlight(in: Capsule())
        }
    }

    var body: some View {
        @Bindable var library = appState.library
        ZStack(alignment: .top) {
            // 照片墙：撑满整个页面，悬浮工具栏以液态玻璃浮层覆盖在上方，
            // 不再挤占独立的一整行——把绝大部分面积留给照片本身。
            Group {
                if appState.library.photoResults.isEmpty {
                    PhotosEmptyStateView()
                } else {
                    PhotoGridView(
                        items: appState.library.photoResults,
                        gridLevel: appState.navigation.gridLevel,
                        badgeMetric: appState.navigation.badgeMetric,
                        selectedIDs: Set([appState.library.selectedPhotoID].compactMap { $0 }),
                        sidebarExpanded: appState.navigation.isSidebarExpanded,
                        topContentInset: gridTopInset,
                        onSidebarExpandedChange: { expanded in
                            appState.navigation.isSidebarExpanded = expanded
                        },
                        onLoadMore: {
                            appState.library.loadMorePhotosIfNeeded()
                        },
                        onZoomStep: { step in
                            appState.navigation.adjustGridLevel(step: step)
                        },
                        onSelect: { result in
                            appState.library.openViewer(for: result)
                        },
                        onSectionsChange: { sections in
                            // 避免在 `updateNSViewController`（视图更新流程内）同步修改 @State，
                            // 否则会触发 "Modifying state during view update" 未定义行为告警。
                            DispatchQueue.main.async { dateSections = sections }
                        },
                        onVisibleDateChange: { date in
                            // 与 `onSectionsChange` 同理：`reportVisibleDate()` 可能在
                            // `updateNSViewController` 触发的布局变化中同步调用
                            // （`NSView.boundsDidChangeNotification` 可能同步派发），
                            // 这里同样延后到下一轮 runloop 再修改 @State，避免
                            // "Modifying state during view update" 告警。
                            DispatchQueue.main.async {
                                currentVisibleDate = date
                                markScrubberActive()
                            }
                        },
                        scrollToIndex: scrollToIndex,
                        onScrollHandled: { scrollToIndex = nil }
                    )
                    .overlay(alignment: .trailing) {
                        if !dateSections.isEmpty {
                            PhotoScrubberView(
                                sections: dateSections,
                                currentDate: currentVisibleDate,
                                isActive: scrubberActive,
                                onScrub: { index in
                                    scrollToIndex = index
                                    markScrubberActive()
                                }
                            )
                        }
                    }
                }

                if appState.library.isRefreshingPhotos {
                    VStack {
                        ProgressView()
                            .controlSize(.small)
                            .padding(10)
                            .liquidGlassBackground(material: .hudWindow, in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.top, gridTopInset + 12)
                }

                if appState.library.isLoadingMorePhotos {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(appState.localized("Loading more photos"))
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .liquidGlassBackground(material: .hudWindow, in: Capsule())
                        .padding(.bottom, 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 悬浮顶部工具栏：始终贴在页面最上方，完全透明的液态玻璃容器，
            // 滚动照片时透出下层内容、不遮挡，把交互压缩为一排。
            VStack(spacing: DesignSystem.Spacing.sm) {
                PhotosToolbarView()
                if appState.library.isTrashViewActive {
                    trashActionBar
                } else if appState.library.isSimilarMode {
                    similarModeBar
                } else if !appState.library.searchFilter.isEmpty {
                    FindAppliedBannerView()
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.top, DesignSystem.Spacing.sm)
        }
        .task {
            await appState.library.refreshPhotosIfNeeded()
        }
        .onChange(of: appState.library.searchFilter) {
            Task { await appState.library.refreshPhotos() }
        }
        .onChange(of: appState.library.pendingScrollAnchorID) {
            restoreScrollAnchorIfNeeded()
        }
        .confirmationDialog(
            "清空废片篓？系统照片将永久删除，本地文件移入系统废纸篓。",
            isPresented: $showEmptyTrashConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                appState.library.emptyTrash()
            }
            Button("取消", role: .cancel) {}
        }
    }

    /// 照片墙顶部预留高度：为悬浮工具栏 + 横幅腾出空间，让第一行照片不被
    /// 浮层初始遮挡。横幅高度按当前是否展示特殊相册横幅动态计算，避免
    /// 出现「空横幅占位但菜单区域过高」的回归（见历史 bug 修复）。
    private var gridTopInset: CGFloat {
        var inset = DesignSystem.Spacing.sm + DesignSystem.Metrics.photosToolbarHeight
        let showsBanner = appState.library.isTrashViewActive
            || appState.library.isSimilarMode
            || !appState.library.searchFilter.isEmpty
        if showsBanner {
            inset += DesignSystem.Spacing.sm + DesignSystem.Metrics.bannerHeight
        }
        return inset + DesignSystem.Spacing.sm
    }

    /// 标记滚动导航为活跃，并在停顿后自动淡出。
    private func markScrubberActive() {
        scrubberActive = true
        scrubberHideTask?.cancel()
        scrubberHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            scrubberActive = false
        }
    }

    /// 「返回」后，把照片墙滚动回 `pendingScrollAnchorID` 所标记的照片，恢复上一次定位。
    private func restoreScrollAnchorIfNeeded() {
        guard let anchorID = appState.library.pendingScrollAnchorID else { return }
        if let index = appState.library.photoResults.firstIndex(where: { $0.id == anchorID }) {
            scrollToIndex = index
        }
        appState.library.pendingScrollAnchorID = nil
    }
}

/// 右侧年/月滚动导航（参考 Google Photos）：滚动时淡入，显示当前年月；
/// 点击年份或上下拖拽可快速跳转到对应年/月第一张照片。
struct PhotoScrubberView: View {
    @Environment(AppState.self) private var appState
    let sections: [GridDateSection]
    let currentDate: Date?
    let isActive: Bool
    var onScrub: (Int) -> Void

    @State private var isDragging = false
    @State private var dragY: CGFloat = 0
    @State private var lastScrubbedIndex = -1

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                yearRail
                pill(in: geo)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .contentShape(Rectangle())
            .gesture(dragGesture(in: geo))
        }
        .frame(width: 48)
        .padding(.trailing, 2)
        .opacity(isActive || isDragging ? 1 : 0)
        .animation(.easeInOut(duration: 0.25), value: isActive)
        .animation(.easeInOut(duration: 0.12), value: isDragging)
    }

    private var yearRail: some View {
        VStack(spacing: 0) {
            ForEach(yearMarkers, id: \.year) { marker in
                Text(verbatim: String(marker.year))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { onScrub(marker.firstIndex) }
            }
        }
        .frame(width: 40)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func pill(in geo: GeometryProxy) -> some View {
        if isDragging, let date = currentDate ?? sections.first?.date {
            Text(monthLabel(date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .liquidGlassBackground(material: .hudWindow, in: Capsule())
                .fixedSize()
                .offset(x: -56, y: min(max(0, dragY - 16), max(0, geo.size.height - 32)))
        }
    }

    private func dragGesture(in geo: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                isDragging = true
                dragY = value.location.y
                guard !sections.isEmpty, geo.size.height > 0 else { return }
                let fraction = min(1, max(0, value.location.y / geo.size.height))
                let rawIndex = Int((fraction * CGFloat(sections.count - 1)).rounded())
                let section = sections[min(max(0, rawIndex), sections.count - 1)]
                if section.firstIndex != lastScrubbedIndex {
                    lastScrubbedIndex = section.firstIndex
                    onScrub(section.firstIndex)
                }
            }
            .onEnded { _ in
                isDragging = false
                lastScrubbedIndex = -1
            }
    }

    /// 每个年份取首个分组（用于年份刻度与点击跳转）。
    private var yearMarkers: [GridDateSection] {
        var seen = Set<Int>()
        return sections.filter { seen.insert($0.year).inserted }
    }

    private func monthLabel(_ date: Date) -> String {
        let isZH = appState.navigation.appLanguage == .zhHans
            || (appState.navigation.appLanguage == .system
                && Locale.preferredLanguages.first?.hasPrefix("zh") == true)
        let formatter = DateFormatter()
        formatter.dateFormat = isZH ? "yyyy年M月" : "MMM yyyy"
        return formatter.string(from: date)
    }
}

struct FindAppliedBannerView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)

            Text("\(appState.localized("Find")): \(summary)")
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer()

            Button {
                appState.navigation.isFindOverlayPresented = true
            } label: {
                Label(appState.localized("Adjust"), systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.pressableGlass)
            .glassHoverHighlight(in: Capsule())

            Button {
                appState.library.searchFilter = SearchFilterState()
            } label: {
                Label(appState.localized("Clear"), systemImage: "xmark")
            }
            .buttonStyle(.pressableGlass)
            .glassHoverHighlight(in: Capsule())
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.bannerHeight)
        .floatingGlassBar()
    }

    private var summary: String {
        var parts: [String] = []
        let filter = appState.library.searchFilter

        let keyword = filter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            parts.append("\"\(keyword)\"")
        }
        if !filter.mediaTypes.isEmpty {
            parts.append("media")
        }
        if filter.screenshotsOnly {
            parts.append("screenshots")
        }
        if let minimum = filter.minimumAestheticScore {
            parts.append("aesthetic>\(Int(minimum.rounded()))")
        }
        if let maximum = filter.maximumAestheticScore {
            parts.append("aesthetic<\(Int(maximum.rounded()))")
        }
        if filter.createdAfter != nil || filter.createdBefore != nil {
            parts.append("time")
        }
        if filter.favoritesOnly {
            parts.append("favorites")
        }
        if filter.includeHidden {
            parts.append("hidden")
        }
        if !filter.deviceCategories.isEmpty {
            parts.append("source")
        }
        if !filter.tagIDs.isEmpty {
            parts.append("tags")
        }
        if !filter.locationNames.isEmpty {
            parts.append("location")
        }
        if !filter.personIDs.isEmpty {
            parts.append("people")
        }

        return parts.isEmpty ? "active filters" : parts.joined(separator: " · ")
    }
}

/// 「特殊相册」横幅：相似照片结果 / 废片篓等"带前置筛选条件的临时相册"统一外观。
///
/// 这是「浏览上下文返回栈」（`BrowseContext`）在 UI 层的标准呈现：左侧图标 + 标题表明
/// 当前处于一个临时的特殊相册中，右侧固定提供「返回」——回到进入前的筛选结果、
/// 滚动位置，并在原先打开过照片详情时重新打开。各相册自身的操作（清除 / 全部恢复 /
/// 清空等）通过 `actions` 传入，排在「返回」之前。
///
/// 后续新增「智能筛选相册」「相册详情」等同类页面，复用这一组件即可获得一致的
/// 外观与返回体验。
struct SpecialAlbumBannerView<Actions: View>: View {
    @Environment(AppState.self) private var appState
    let icon: String
    let title: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)

            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)

            Spacer()

            actions()

            Button {
                appState.library.goBack()
            } label: {
                Label(appState.localized("Back"), systemImage: "chevron.left")
            }
            .buttonStyle(.pressableGlass)
            .glassHoverHighlight(in: Capsule())
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.bannerHeight)
        .floatingGlassBar()
    }
}

struct PhotosToolbarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        // 参考系统照片 App 顶部工具栏：每个功能分组各自一颗独立的悬浮液态玻璃
        // 胶囊/圆形按钮，组间留白透出照片墙，而不是合并成贯穿整行的长条
        // （那曾是 `floatingGlassBar()` 套在整个 HStack 外的旧版做法）。
        //
        // 去掉左侧「照片」标题 + 计数胶囊与导入按钮：标题文字与项目树已随顶部
        // 菜单栏一起移除，筛选条件与匹配数量改由底部工具栏展示；导入按钮迁移
        // 到设置页「照片源」的系统图库行（仅图库不可访问时显示，逻辑不变）。
        // 精简后顶部悬浮工具栏只保留与「当前网格视图」直接相关的操作，整组靠右。
        HStack(spacing: 10) {
            Spacer()

            Menu {
                Button {
                    appState.analysis.scoreVisiblePhotos()
                } label: {
                    Label(appState.localized("Score Loaded Photos"), systemImage: "rectangle.grid.3x2")
                }
                .disabled(appState.library.photoResults.isEmpty)

                Button {
                    appState.analysis.scoreAllMatchedPhotos()
                } label: {
                    Label(appState.localized("Score All Matched"), systemImage: "square.stack.3d.up")
                }
                .disabled(appState.library.matchedPhotoCount == 0)

                Divider()

                Button {
                    appState.analysis.retryFailedAnalysis()
                } label: {
                    Label(appState.localized("Retry Failed"), systemImage: "arrow.clockwise")
                }
            } label: {
                Label(appState.localized("Score"), systemImage: "sparkles")
            }
            .disabled(appState.analysis.analysisProgress.isRunning)
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .floatingGlassCapsule()
            .glassHoverHighlight(in: Capsule())

            ZoomControlView()

            BadgeSegmentView()

            sortMenu
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.photosToolbarHeight)
    }

    /// 排序菜单：与「评分」菜单同款外观——液态玻璃胶囊里的系统 `Menu`，按钮本身
    /// 展示当前排序方式的图标+文字，点击展开 4 个选项（各自带方向/星标图标）。
    /// 比旧版固定宽度 170pt、套在 `.floatingGlassCapsule()` 里的 `Picker` 更窄、
    /// 随内容自适应宽度，且不是「组件套组件」。
    private var sortMenu: some View {
        let current = appState.library.searchFilter.sortMode
        return Menu {
            ForEach(SortMode.allCases) { mode in
                Button {
                    appState.library.searchFilter.sortMode = mode
                } label: {
                    Label(appState.localized(mode.localizationKey), systemImage: mode.iconName)
                }
            }
        } label: {
            Label(appState.localized(current.localizationKey), systemImage: current.iconName)
        }
        .menuStyle(.borderlessButton)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .floatingGlassCapsule()
        .glassHoverHighlight(in: Capsule())
    }
}

struct ZoomControlView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 2) {
            Button {
                appState.navigation.adjustGridLevel(step: 1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
            }
            .disabled(currentIndex >= GridLevel.allCases.count - 1)
            .help(appState.localized("Zoom out"))
            .glassHoverHighlight(in: Circle())

            // 浅色竖线分隔加 / 减按钮，呼应系统照片 App 缩放控件的分段感。
            Rectangle()
                .fill(DesignSystem.Glass.hairline)
                .frame(width: DesignSystem.Glass.hairlineWidth, height: 16)

            Button {
                appState.navigation.adjustGridLevel(step: -1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .disabled(currentIndex <= 0)
            .help(appState.localized("Zoom in"))
            .glassHoverHighlight(in: Circle())
        }
        // 与「导入 / 评分」等按钮一致的按下反馈（轻微缩小 + 减淡），
        // 替换原 `.borderless`：那只提供系统默认 hover 样式，缺少按下回弹。
        .buttonStyle(.pressableGlass)
        .padding(4)
        .floatingGlassCapsule()
    }

    private var currentIndex: Int {
        GridLevel.allCases.firstIndex(of: appState.navigation.gridLevel) ?? 1
    }
}

struct BadgeSegmentView: View {
    @Environment(AppState.self) private var appState

    /// 列数 ≥ 15 时强制不显示角标，此控件仅用于切换维度（呈隐藏态）。
    private var badgeHidden: Bool { appState.navigation.gridLevel.columnCount >= 15 }

    var body: some View {
        HStack(spacing: 2) {
            segment(.aesthetic, icon: "camera.aperture")
            segment(.overall, icon: "star")
        }
        .padding(3)
        .floatingGlassCapsule()
        .opacity(badgeHidden ? 0.55 : 1)
        .help(badgeHidden ? "高密度下不显示分数角标，仅可切换维度" : "分数维度")
    }

    private func segment(_ metric: BadgeMetric, icon: String) -> some View {
        let selected = appState.navigation.badgeMetric == metric
        return Button {
            // 高密度：仅切换维度、不开启展示；正常：点同一维度切换显隐。
            appState.navigation.badgeMetric = badgeHidden ? metric : (selected ? .hidden : metric)
        } label: {
            Label(appState.localized(metric.localizationKey), systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        // 与其它玻璃按钮统一按下反馈（轻微缩小 + 减淡）。
        .buttonStyle(.pressableGlass)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(selected ? (badgeHidden ? Color.secondary : Color.white) : Color.secondary)
        .background {
            if selected, !badgeHidden {
                Capsule().fill(DesignSystem.Glass.activeTint)
            }
        }
        .glassHoverHighlight(in: Capsule())
    }
}

struct PhotosEmptyStateView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: emptyIcon)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)

            Text(emptyTitle)
                .font(.title3.weight(.semibold))

            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if appState.library.importProgress.phase == .initialImport || appState.library.importProgress.phase == .backgroundImport {
                ProgressView(value: Double(appState.library.importProgress.imported), total: Double(max(1, appState.library.importProgress.total)))
                    .frame(width: 280)
            } else {
                Button {
                    appState.library.startImport()
                } label: {
                    Label("Import Photos", systemImage: "photo.stack")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
    }

    private var emptyIcon: String {
        switch appState.library.importProgress.phase {
        case .denied:
            "lock"
        case .failed:
            "exclamationmark.triangle"
        default:
            "photo.on.rectangle.angled"
        }
    }

    private var emptyTitle: String {
        switch appState.library.importProgress.phase {
        case .denied:
            "Photos access needed"
        case .failed:
            "Import failed"
        case .initialImport, .backgroundImport:
            "Loading your library"
        default:
            appState.library.searchFilter.isEmpty ? "No photos imported yet" : "No matching photos"
        }
    }

    private var emptyMessage: String {
        switch appState.library.importProgress.phase {
        case .denied:
            "Allow Photos access in System Settings, then import again."
        case .failed:
            appState.library.importProgress.message
        case .initialImport, .backgroundImport:
            "\(appState.library.importProgress.message) · \(appState.library.importProgress.imported)/\(appState.library.importProgress.total)"
        default:
            appState.library.searchFilter.isEmpty
                ? "MantaPhotos imports lightweight metadata first so the first screen can appear quickly."
                : "The current search and filters do not match imported photos."
        }
    }
}
