import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var tagQuery = ""
    @State private var showsAllTagOptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !appState.library.searchFilter.isEmpty {
                    Button {
                        appState.library.searchFilter = SearchFilterState()
                    } label: {
                        Label(appState.localized("Clear Filters"), systemImage: "xmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }

                sidebarSection(appState.localized("Type"), isActive: isTypeActive, clear: clearType) {
                    chipRow {
                        filterChip(appState.localized("Photos"), icon: "photo", active: appState.library.searchFilter.mediaTypes == [.image]) {
                            toggleSingleMediaType(.image)
                        }
                        filterChip(appState.localized("Videos"), icon: "video", active: appState.library.searchFilter.mediaTypes == [.video]) {
                            toggleSingleMediaType(.video)
                        }
                        filterChip(appState.localized("Live"), icon: "livephoto", active: appState.library.searchFilter.mediaTypes == [.livePhoto]) {
                            toggleSingleMediaType(.livePhoto)
                        }
                        filterChip(appState.localized("Screenshots"), icon: "iphone", active: appState.library.searchFilter.screenshotsOnly) {
                            appState.library.searchFilter.mediaTypes = []
                            appState.library.searchFilter.screenshotsOnly.toggle()
                        }
                    }
                }

                sidebarSection(appState.localized("Score"), isActive: isScoreActive, clear: clearScore) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.aperture")
                                .foregroundStyle(.secondary)
                            Text(appState.localized("Aesthetic"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let summary = appState.library.searchFilter.scoreFilterSummaryCompact(localizer: appState.localized) {
                                Text(summary)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Text("0")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            RangeSliderView(lowerValue: lowerScoreValue, upperValue: upperScoreValue)
                            Text("100")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        // 高分照片 / 低分照片 快捷筛选：与详情页的“四档评分”阈值呼应（高档 ≥80，低档 <40）。
                        // 单选语义：再点一次同一项即清空（与类型/来源等其余分区的快捷筛选一致）。
                        chipRow {
                            filterChip(appState.localized("High Score Photos"), icon: "star.fill", active: isHighScoreQuickFilterActive) {
                                toggleHighScoreQuickFilter()
                            }
                            filterChip(appState.localized("Low Score Photos"), icon: "arrow.down.right", active: isLowScoreQuickFilterActive) {
                                toggleLowScoreQuickFilter()
                            }
                        }
                    }
                }

                sidebarSection(appState.localized("Time"), isActive: isTimeActive, clear: clearTime) {
                    chipRow {
                        filterChip(appState.localized("Today"), icon: "sun.max", active: isToday) {
                            setToday()
                        }
                        filterChip(appState.localized("3 days"), icon: "clock", active: isTimeRange(days: 3)) {
                            setRecentDays(3)
                        }
                        filterChip(appState.localized("Week"), icon: "calendar", active: isTimeRange(days: 7)) {
                            setRecentDays(7)
                        }
                        filterChip(appState.localized("Month"), icon: "calendar.badge.clock", active: isCurrentMonth) {
                            setCurrentMonth()
                        }
                        filterChip(appState.localized("Near Month"), icon: "calendar", active: isTimeRange(days: 30)) {
                            setRecentDays(30)
                        }
                        filterChip(appState.localized("This Year"), icon: "calendar.circle", active: isCurrentYear) {
                            setCurrentYear()
                        }
                    }
                }

                sidebarSection(appState.localized("Status"), isActive: isStatusActive, clear: clearStatus) {
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarItem(appState.localized("Favorites"), icon: "heart", active: appState.library.searchFilter.favoritesOnly) {
                            appState.library.searchFilter.favoritesOnly.toggle()
                        }
                        sidebarItem(appState.localized("Duplicate"), icon: "doc.on.doc", active: false) {}
                            .disabled(true)
                        sidebarItem(appState.localized("Trash"), icon: "trash", active: appState.library.isTrashViewActive) {
                            appState.library.toggleTrashView()
                        }
                    }
                }

                sidebarSection(appState.localized("Source"), isActive: isSourceActive, clear: clearDeviceSource) {
                    // 两排各 3 项：第一排 手机 / 卡片机 / 单反相机，第二排 运动相机 / 无人机 / 截屏。
                    // 单反相机排到运动相机之前，符合「先常规设备、后特殊设备」的顺序直觉。
                    chipRow {
                        sourceChip(.phone, icon: "iphone")
                        sourceChip(.pocket, icon: "camera.viewfinder")
                        sourceChip(.camera, icon: "camera")
                        sourceChip(.actionCamera, icon: "figure.run")
                        sourceChip(.drone, icon: "airplane")
                        sourceChip(.screenshot, icon: "rectangle.on.rectangle")
                    }
                }

                sidebarSection(appState.localized("Tags"), isActive: false, clear: {}) {
                    TextField(appState.localized("Search tags"), text: $tagQuery)
                        .textFieldStyle(.roundedBorder)
                    chipRow {
                        ForEach(visibleTagOptions, id: \.title) { option in
                            disabledChip(appState.localized(option.title), icon: option.icon)
                        }
                        filterChip(appState.localized(showsAllTagOptions ? "Less" : "More"), icon: showsAllTagOptions ? "chevron.up" : "chevron.down", active: false) {
                            showsAllTagOptions.toggle()
                        }
                    }
                }

            }
            .padding(16)
        }
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        isActive: Bool,
        clear: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if isActive {
                    Button {
                        clear()
                    } label: {
                        // 显式给图标按钮一个固定的可点击区域 + `contentShape`：
                        // SF Symbol 字形本身的可见区域很小且不规则，纯 `Image` 作为
                        // `.borderless` 按钮的 label 时，命中区域会收缩到字形实际像素，
                        // 叠加 `glassHoverHighlight` 的 `scaleEffect` 后命中区域与可见
                        // 高光进一步错位，导致「看起来在按钮上，点击却无效」。
                        Image(systemName: "xmark")
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .glassHoverHighlight(in: Circle())
                }
            }
            content()
        }
    }

    private func chipRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        FlowLayout(spacing: 6) {
            content()
        }
    }

    private func filterChip(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .foregroundStyle(active ? .white : .secondary)
                .background(
                    active ? AnyShapeStyle(DesignSystem.Glass.activeTint) : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func sourceChip(_ category: DeviceCategory, icon: String) -> some View {
        filterChip(
            appState.localized(sourceTitle(category)),
            icon: icon,
            active: appState.library.searchFilter.deviceCategories == [category]
        ) {
            appState.library.searchFilter.deviceCategories = appState.library.searchFilter.deviceCategories == [category] ? [] : [category]
            if category == .screenshot {
                appState.library.searchFilter.screenshotsOnly = appState.library.searchFilter.deviceCategories == [category]
                appState.library.searchFilter.mediaTypes = []
            } else {
                appState.library.searchFilter.screenshotsOnly = false
            }
        }
    }

    private func sourceTitle(_ category: DeviceCategory) -> String {
        switch category {
        case .phone: "Phone"
        case .pocket: "Pocket"
        case .actionCamera: "Action Cam"
        case .drone: "Drone"
        case .camera: "SLR Camera"
        case .screenshot: "Screenshot"
        case .unknown: "Unknown"
        }
    }

    private func disabledChip(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(.tertiary)
            .background(.quaternary, in: Capsule())
    }

    private func sidebarItem(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(active ? .primary : .secondary)
            .background(active ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func toggleSingleMediaType(_ mediaType: MediaType) {
        appState.library.searchFilter.screenshotsOnly = false
        appState.library.searchFilter.mediaTypes = appState.library.searchFilter.mediaTypes == [mediaType] ? [] : [mediaType]
    }

    private var lowerScoreValue: Binding<Double> {
        Binding(
            get: { appState.library.searchFilter.minimumAestheticScore ?? 0 },
            set: { newValue in
                let clamped = min(max(0, newValue), upperScoreValue.wrappedValue)
                appState.library.searchFilter.minimumAestheticScore = clamped <= 0 ? nil : clamped
            }
        )
    }

    private var upperScoreValue: Binding<Double> {
        Binding(
            get: { appState.library.searchFilter.maximumAestheticScore ?? 100 },
            set: { newValue in
                let clamped = max(min(100, newValue), lowerScoreValue.wrappedValue)
                appState.library.searchFilter.maximumAestheticScore = clamped >= 100 ? nil : clamped
            }
        )
    }

    private var isHighScoreQuickFilterActive: Bool {
        appState.library.searchFilter.isHighScoreQuickFilterActive
    }

    private var isLowScoreQuickFilterActive: Bool {
        appState.library.searchFilter.isLowScoreQuickFilterActive
    }

    private func toggleHighScoreQuickFilter() {
        appState.library.searchFilter.toggleHighScoreQuickFilter()
    }

    private func toggleLowScoreQuickFilter() {
        appState.library.searchFilter.toggleLowScoreQuickFilter()
    }

    private var isScoreActive: Bool {
        appState.library.searchFilter.minimumAestheticScore != nil || appState.library.searchFilter.maximumAestheticScore != nil
    }

    private var isTypeActive: Bool {
        !appState.library.searchFilter.mediaTypes.isEmpty || appState.library.searchFilter.screenshotsOnly
    }

    private var isTimeActive: Bool {
        appState.library.searchFilter.createdAfter != nil || appState.library.searchFilter.createdBefore != nil
    }

    private var isStatusActive: Bool {
        appState.library.searchFilter.favoritesOnly
    }

    private var isSourceActive: Bool {
        !appState.library.searchFilter.deviceCategories.isEmpty
    }

    private var visibleTagOptions: [SidebarTagOption] {
        let all = [
            SidebarTagOption(title: "Landscape", icon: "mountain.2"),
            SidebarTagOption(title: "People", icon: "person"),
            SidebarTagOption(title: "Architecture", icon: "building.2"),
            SidebarTagOption(title: "Food", icon: "fork.knife"),
            SidebarTagOption(title: "Travel", icon: "airplane"),
            SidebarTagOption(title: "Night", icon: "moon.stars"),
            SidebarTagOption(title: "Pet", icon: "pawprint")
        ]
        let query = tagQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = query.isEmpty ? all : all.filter { appState.localized($0.title).lowercased().contains(query) || $0.title.lowercased().contains(query) }
        return showsAllTagOptions || !query.isEmpty ? filtered : Array(filtered.prefix(5))
    }

    private func clearType() {
        appState.library.searchFilter.mediaTypes = []
        appState.library.searchFilter.screenshotsOnly = false
    }

    private func clearScore() {
        appState.library.searchFilter.minimumAestheticScore = nil
        appState.library.searchFilter.maximumAestheticScore = nil
    }

    private func clearTime() {
        appState.library.searchFilter.createdAfter = nil
        appState.library.searchFilter.createdBefore = nil
    }

    private func clearStatus() {
        appState.library.searchFilter.favoritesOnly = false
        appState.library.searchFilter.includeHidden = false
    }

    private func clearDeviceSource() {
        appState.library.searchFilter.deviceCategories = []
        appState.library.searchFilter.screenshotsOnly = false
    }

    private func setRecentDays(_ days: Int) {
        if isTimeRange(days: days) {
            clearTime()
            return
        }
        appState.library.searchFilter.createdAfter = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        appState.library.searchFilter.createdBefore = nil
    }

    private func setToday() {
        if isToday {
            clearTime()
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        appState.library.searchFilter.createdAfter = start
        appState.library.searchFilter.createdBefore = Calendar.current.date(byAdding: .day, value: 1, to: start)
    }

    private func setCurrentMonth() {
        if isCurrentMonth {
            clearTime()
            return
        }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))
        appState.library.searchFilter.createdAfter = start
        appState.library.searchFilter.createdBefore = nil
    }

    private func setCurrentYear() {
        if isCurrentYear {
            clearTime()
            return
        }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))
        appState.library.searchFilter.createdAfter = start
        appState.library.searchFilter.createdBefore = nil
    }

    private func isTimeRange(days: Int) -> Bool {
        guard let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let expected = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return abs(createdAfter.timeIntervalSince(expected)) < 5
            && appState.library.searchFilter.createdBefore == nil
    }

    private var isCurrentMonth: Bool {
        guard let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date()))
        return createdAfter == start && appState.library.searchFilter.createdBefore == nil
    }

    private var isCurrentYear: Bool {
        guard let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let start = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date()))
        return createdAfter == start && appState.library.searchFilter.createdBefore == nil
    }

    private var isToday: Bool {
        guard let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)
        return createdAfter == start && appState.library.searchFilter.createdBefore == end
    }
}

private struct SidebarTagOption {
    var title: String
    var icon: String
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 220
        let rows = rows(width: width, subviews: subviews)
        return CGSize(width: width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> (height: CGFloat, rowCount: Int) {
        var x: CGFloat = 0
        var height: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowCount = 1

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                height += rowHeight + spacing
                x = 0
                rowHeight = 0
                rowCount += 1
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return (height + rowHeight, rowCount)
    }
}
