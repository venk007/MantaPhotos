import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState
    @State private var peopleQuery = ""
    @State private var tagQuery = ""
    @State private var showsAllTagOptions = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sidebarSection(appState.localized("Type"), clear: clearType) {
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

                sidebarSection(appState.localized("Score"), clear: clearScore) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "camera.aperture")
                                .foregroundStyle(.secondary)
                            Text(appState.localized("Aesthetic"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 2) {
                                scoreOperatorButton(">", active: scoreOperator == .greaterThan) {
                                    scoreOperator = .greaterThan
                                }
                                scoreOperatorButton("<", active: scoreOperator == .lessThan) {
                                    scoreOperator = .lessThan
                                }
                            }
                            Spacer()
                            Text("\(Int(currentScoreValue.rounded()))")
                                .font(.caption.monospacedDigit())
                                .frame(width: 28, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            Text("0")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: scoreValue,
                                in: 0...100,
                                step: 1
                            )
                            Text("100")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        chipRow {
                            filterChip(appState.localized("High"), icon: "sparkles", active: appState.library.searchFilter.minimumAestheticScore == 80) {
                                appState.library.searchFilter.minimumAestheticScore = appState.library.searchFilter.minimumAestheticScore == 80 ? nil : 80
                                appState.library.searchFilter.maximumAestheticScore = nil
                            }
                            filterChip(appState.localized("Low"), icon: "chart.line.downtrend.xyaxis", active: appState.library.searchFilter.maximumAestheticScore == 40) {
                                appState.library.searchFilter.maximumAestheticScore = appState.library.searchFilter.maximumAestheticScore == 40 ? nil : 40
                                appState.library.searchFilter.minimumAestheticScore = nil
                            }
                        }
                    }
                }

                sidebarSection(appState.localized("Time"), clear: clearTime) {
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

                sidebarSection(appState.localized("Status"), clear: clearStatus) {
                    VStack(alignment: .leading, spacing: 6) {
                        sidebarItem(appState.localized("Favorites"), icon: "heart", active: appState.library.searchFilter.favoritesOnly) {
                            appState.library.searchFilter.favoritesOnly.toggle()
                        }
                        sidebarItem(appState.localized("Duplicate"), icon: "doc.on.doc", active: false) {}
                            .disabled(true)
                        sidebarItem(appState.localized("Trash"), icon: "trash", active: appState.library.searchFilter.inTrash == true) {
                            appState.library.searchFilter.inTrash = appState.library.searchFilter.inTrash == true ? false : true
                        }
                    }
                }

                sidebarSection(appState.localized("Source"), clear: clearDeviceSource) {
                    chipRow {
                        sourceChip(.phone, icon: "iphone")
                        sourceChip(.pocket, icon: "camera.viewfinder")
                        sourceChip(.actionCamera, icon: "figure.run")
                        sourceChip(.drone, icon: "airplane")
                        sourceChip(.camera, icon: "camera")
                        sourceChip(.screenshot, icon: "rectangle.on.rectangle")
                    }
                }

                sidebarSection(appState.localized("People"), clear: {}) {
                    TextField(appState.localized("Search people"), text: $peopleQuery)
                        .textFieldStyle(.roundedBorder)
                    chipRow {
                        disabledChip(appState.localized("Family"), icon: "person.2")
                        disabledChip(appState.localized("Friends"), icon: "person.3")
                    }
                }

                sidebarSection(appState.localized("Tags"), clear: {}) {
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

                Button {
                    appState.library.searchFilter = SearchFilterState()
                } label: {
                    Label(appState.localized("Clear Filters"), systemImage: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private func sidebarSection<Content: View>(
        _ title: String,
        clear: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    clear()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
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
                    active
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color(red: 0.37, green: 0.36, blue: 0.90), Color(red: 0.75, green: 0.35, blue: 0.95)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(.quaternary),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func scoreOperatorButton(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 20)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(activeGradient) : AnyShapeStyle(.quaternary), in: RoundedRectangle(cornerRadius: 5))
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
        case .camera: "Camera"
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

    private var activeGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.37, green: 0.36, blue: 0.90), Color(red: 0.75, green: 0.35, blue: 0.95)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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

    private var scoreOperator: SidebarScoreOperator {
        get {
            appState.library.searchFilter.maximumAestheticScore == nil ? .greaterThan : .lessThan
        }
        nonmutating set {
            let value = currentScoreValue
            if newValue == .greaterThan {
                appState.library.searchFilter.minimumAestheticScore = value <= 1 ? nil : value
                appState.library.searchFilter.maximumAestheticScore = nil
            } else {
                appState.library.searchFilter.maximumAestheticScore = value <= 1 ? nil : value
                appState.library.searchFilter.minimumAestheticScore = nil
            }
        }
    }

    private var scoreValue: Binding<Double> {
        Binding(
            get: { currentScoreValue },
            set: { setScoreValue($0.rounded()) }
        )
    }

    private var currentScoreValue: Double {
        appState.library.searchFilter.maximumAestheticScore ?? appState.library.searchFilter.minimumAestheticScore ?? 0
    }

    private func setScoreValue(_ value: Double) {
        let normalized = min(100, max(0, value))
        if scoreOperator == .greaterThan {
            appState.library.searchFilter.minimumAestheticScore = normalized <= 1 ? nil : normalized
            appState.library.searchFilter.maximumAestheticScore = nil
        } else {
            appState.library.searchFilter.maximumAestheticScore = normalized <= 1 ? nil : normalized
            appState.library.searchFilter.minimumAestheticScore = nil
        }
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
        appState.library.searchFilter.inTrash = false
    }

    private func clearTime() {
        appState.library.searchFilter.createdAfter = nil
        appState.library.searchFilter.createdBefore = nil
    }

    private func clearStatus() {
        appState.library.searchFilter.favoritesOnly = false
        appState.library.searchFilter.includeHidden = false
        appState.library.searchFilter.inTrash = false
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

private enum SidebarScoreOperator {
    case greaterThan
    case lessThan
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
