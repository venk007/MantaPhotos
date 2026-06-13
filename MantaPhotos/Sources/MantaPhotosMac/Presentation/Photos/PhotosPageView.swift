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
            .buttonStyle(.borderless)
            Button(role: .destructive) {
                showEmptyTrashConfirm = true
            } label: {
                Label("清空（永久删除）", systemImage: "trash")
            }
            .buttonStyle(.borderless)
        }
    }

    private var similarModeBar: some View {
        SpecialAlbumBannerView(icon: "rectangle.on.rectangle.angled", title: appState.localized("Similar Photos Results")) {
            Button {
                appState.library.exitSimilarMode()
            } label: {
                Label(appState.localized("Clear"), systemImage: "xmark")
            }
            .buttonStyle(.borderless)
        }
    }

    var body: some View {
        @Bindable var library = appState.library
        VStack(spacing: 0) {
            PhotosToolbarView()
            if appState.library.isTrashViewActive {
                trashActionBar
            } else if appState.library.isSimilarMode {
                similarModeBar
            } else if !appState.library.searchFilter.isEmpty {
                FindAppliedBannerView()
            }
            Divider()
            ZStack {
                if appState.library.photoResults.isEmpty {
                    PhotosEmptyStateView()
                } else {
                    PhotoGridView(
                        items: appState.library.photoResults,
                        gridLevel: appState.navigation.gridLevel,
                        badgeMetric: appState.navigation.badgeMetric,
                        selectedIDs: Set([appState.library.selectedPhotoID].compactMap { $0 }),
                        sidebarExpanded: appState.navigation.isSidebarExpanded,
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
                        onSectionsChange: { dateSections = $0 },
                        onVisibleDateChange: { date in
                            currentVisibleDate = date
                            markScrubberActive()
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
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        Spacer()
                    }
                    .padding(.top, 12)
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
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 18)
                    }
                }
            }
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
        .sheet(isPresented: $library.isViewerPresented) {
            if let result = appState.library.selectedPhotoForViewer {
                PhotoViewerView(result: result)
                    .environment(appState)
            }
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
                .glassEffect(.regular, in: Capsule())
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
            .buttonStyle(.borderless)

            Button {
                appState.library.searchFilter = SearchFilterState()
            } label: {
                Label(appState.localized("Clear"), systemImage: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.bannerHeight)
        .background(.regularMaterial)
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
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: DesignSystem.Metrics.bannerHeight)
        .background(.regularMaterial)
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

struct PhotosToolbarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var library = appState.library
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.localized("Photos"))
                    .font(.title3.weight(.semibold))
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.library.startImport()
            } label: {
                Label(appState.localized("Import"), systemImage: "photo.on.rectangle")
            }
            .disabled(appState.library.importProgress.phase == .initialImport || appState.library.importProgress.phase == .backgroundImport)

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
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.panel))
            .glassHoverHighlight(in: RoundedRectangle(cornerRadius: DesignSystem.Radius.panel))

            ZoomControlView()

            BadgeSegmentView()

            Picker(appState.localized("Sort"), selection: $library.searchFilter.sortMode) {
                ForEach(SortMode.allCases) { mode in
                    Text(appState.localized(mode.localizationKey)).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 190)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .frame(height: 58)
    }

    private var countText: String {
        if appState.library.matchedPhotoCount == appState.library.photoResults.count {
            switch appState.navigation.appLanguage {
            case .zhHans:
                return "\(appState.library.photoResults.count.formatted()) 张可见"
            case .system where Locale.preferredLanguages.first?.hasPrefix("zh") == true:
                return "\(appState.library.photoResults.count.formatted()) 张可见"
            default:
                return "\(appState.library.photoResults.count.formatted()) visible"
            }
        }
        switch appState.navigation.appLanguage {
        case .zhHans:
            return "\(appState.library.photoResults.count.formatted()) 已加载 · \(appState.library.matchedPhotoCount.formatted()) 匹配"
        case .system where Locale.preferredLanguages.first?.hasPrefix("zh") == true:
            return "\(appState.library.photoResults.count.formatted()) 已加载 · \(appState.library.matchedPhotoCount.formatted()) 匹配"
        default:
            return "\(appState.library.photoResults.count.formatted()) loaded · \(appState.library.matchedPhotoCount.formatted()) matched"
        }
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
                    .frame(width: 22, height: 22)
            }
            .disabled(currentIndex >= GridLevel.allCases.count - 1)
            .help(appState.localized("Zoom out"))
            .glassHoverHighlight(in: Circle())

            Button {
                appState.navigation.adjustGridLevel(step: -1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 22, height: 22)
            }
            .disabled(currentIndex <= 0)
            .help(appState.localized("Zoom in"))
            .glassHoverHighlight(in: Circle())
        }
        .buttonStyle(.borderless)
        .padding(4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.panel))
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
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.panel))
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
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(selected ? (badgeHidden ? Color.secondary : Color.white) : Color.secondary)
        .background {
            if selected, !badgeHidden {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                    .fill(DesignSystem.Glass.activeTint)
            }
        }
        .glassHoverHighlight(in: RoundedRectangle(cornerRadius: DesignSystem.Radius.control))
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
