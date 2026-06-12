import SwiftUI

struct FindOverlayView: View {
    @Environment(AppState.self) private var appState
    @FocusState private var queryFocused: Bool
    @State private var sidebarWasExpanded = false
    @State private var tagOptions: [PhotoTagOption] = []

    var body: some View {
        @Bindable var library = appState.library
        ZStack {
            (appState.navigation.themeMode == .light ? DesignSystem.Glass.scrimLight : DesignSystem.Glass.scrimDark)
                .ignoresSafeArea()
                .onTapGesture {
                    appState.navigation.isFindOverlayPresented = false
                }

            VStack(spacing: 0) {
                header
                countBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        mediaSection
                        scoreSection
                        dateSection
                        statusSection
                        sourceSection
                        locationSection
                        peopleSection
                        tagSection
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                }
                footer
            }
            .frame(width: 760, height: 660)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.overlay))
            .shadow(color: .black.opacity(0.24), radius: 30, x: 0, y: 16)
        }
        .onAppear {
            sidebarWasExpanded = appState.navigation.isSidebarExpanded
            appState.navigation.isSidebarExpanded = false
            queryFocused = true
        }
        .onDisappear {
            if appState.navigation.route == .photos {
                appState.navigation.isSidebarExpanded = sidebarWasExpanded
            }
        }
        .onExitCommand {
            appState.navigation.isFindOverlayPresented = false
        }
    }

    @ViewBuilder private var header: some View {
        @Bindable var library = appState.library
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(appState.localized("Find placeholder"), text: $library.searchFilter.keyword)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($queryFocused)

                if !appState.library.searchFilter.keyword.isEmpty {
                    Button {
                        appState.library.searchFilter.keyword = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: DesignSystem.Radius.card))

            if currentModelSupportsText {
                Button {
                    runSemanticSearch()
                } label: {
                    Label("语义搜索", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.bordered)
                .disabled(appState.library.searchFilter.keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Button {
                appState.library.searchFilter = SearchFilterState()
            } label: {
                Label(appState.localized("Reset"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)

            Button {
                appState.navigation.isFindOverlayPresented = false
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help(appState.localized("Close"))
        }
        .padding(18)
    }

    private var currentModelSupportsText: Bool {
        EmbeddingProviderRegistry.allDescriptors
            .first { $0.key == appState.navigation.vectorModelKey }?.supportsTextQuery ?? false
    }

    private func runSemanticSearch() {
        appState.library.semanticSearch(
            query: appState.library.searchFilter.keyword,
            spaceKey: appState.navigation.vectorModelKey
        )
        appState.navigation.isFindOverlayPresented = false
    }

    private var countBar: some View {
        HStack(spacing: 12) {
            Text(countText)
                .font(.callout.weight(.semibold))
            Label(appState.localized("Photos page updates in real time"), systemImage: "bolt.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 10)
        .background(.quaternary)
    }

    private var mediaSection: some View {
        findSection("Media Type", icon: "photo.on.rectangle.angled", isClearVisible: isMediaActive) {
            appState.library.searchFilter.mediaTypes = []
            appState.library.searchFilter.screenshotsOnly = false
        } content: {
            FlowLayout(spacing: 8) {
                chip("Photos", icon: "photo", active: appState.library.searchFilter.mediaTypes.contains(.image)) {
                    toggleMediaType(.image)
                }
                chip("Videos", icon: "video", active: appState.library.searchFilter.mediaTypes.contains(.video)) {
                    toggleMediaType(.video)
                }
                chip("Live", icon: "livephoto", active: appState.library.searchFilter.mediaTypes.contains(.livePhoto)) {
                    toggleMediaType(.livePhoto)
                }
                chip("Screenshots", icon: "iphone", active: appState.library.searchFilter.screenshotsOnly) {
                    appState.library.searchFilter.mediaTypes = []
                    appState.library.searchFilter.screenshotsOnly.toggle()
                }
            }
        }
    }

    private var scoreSection: some View {
        findSection("Score", icon: "star", isClearVisible: isScoreActive, clear: clearScore) {
            VStack(alignment: .leading, spacing: 12) {
                FlowLayout(spacing: 6) {
                    scoreDimensionChip("Aesthetic", icon: "camera.aperture", active: true, enabled: true)
                    scoreDimensionChip("Overall", icon: "chart.line.uptrend.xyaxis", active: false, enabled: false)
                    scoreDimensionChip("Technical", icon: "wrench.and.screwdriver", active: false, enabled: false)
                    scoreDimensionChip("Content", icon: "square.text.square", active: false, enabled: false)
                    scoreDimensionChip("Emotion", icon: "heart", active: false, enabled: false)
                    scoreDimensionChip("Rarity", icon: "sparkles", active: false, enabled: false)
                    scoreDimensionChip("Unique", icon: "diamond", active: false, enabled: false)
                }

                HStack(spacing: 10) {
                    segmentedOperator("Greater Than", active: scoreOperator == .greaterThan) {
                        scoreOperator = .greaterThan
                    }
                    segmentedOperator("Less Than", active: scoreOperator == .lessThan) {
                        scoreOperator = .lessThan
                    }
                    Spacer()
                }

                HStack(spacing: 10) {
                    Text("0")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: scoreValue, in: 0...100, step: 1)
                    Text("100")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(value: scoreIntValue, in: 0...100) {
                        Text("\(Int(currentScoreValue))")
                            .font(.callout.monospacedDigit())
                            .frame(width: 36, alignment: .trailing)
                    }
                    .labelsHidden()
                }

                Text(scoreHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var dateSection: some View {
        findSection("Time Range", icon: "calendar", isClearVisible: isTimeActive, clear: clearTime) {
            VStack(alignment: .leading, spacing: 9) {
                dateRow(icon: "calendar.day.timeline.leading") {
                    dateChip("Today", active: isToday) { setToday() }
                    dateChip("Yesterday", active: isYesterday) { setYesterday() }
                    dateChip("3 days", active: isRecentDays(3)) { setRecentDays(3) }
                }
                dateRow(icon: "calendar.badge.clock") {
                    dateChip("This Week", active: isCurrentWeek) { setCurrentWeek() }
                    dateChip("Near Week", active: isRecentDays(7)) { setRecentDays(7) }
                    dateChip("Last Week", active: isLastWeek) { setLastWeek() }
                    dateChip("Two Weeks", active: isRecentDays(14)) { setRecentDays(14) }
                }
                dateRow(icon: "calendar") {
                    dateChip("Month", active: isCurrentMonth) { setCurrentMonth() }
                    dateChip("Near Month", active: isRecentDays(30)) { setRecentDays(30) }
                    dateChip("Last Month", active: isLastMonth) { setLastMonth() }
                    dateChip("Three Months", active: isRecentDays(90)) { setRecentDays(90) }
                    dateChip("Six Months", active: isRecentDays(180)) { setRecentDays(180) }
                }
                dateRow(icon: "calendar.circle") {
                    dateChip("This Year", active: isCurrentYear) { setCurrentYear() }
                    dateChip("Last Year", active: isLastYear) { setLastYear() }
                    dateChip("Recent Years", active: isRecentYears) { setRecentYears() }
                }
                dateRow(icon: "sparkles") {
                    disabledChip("Last Trip", icon: "map")
                    disabledChip("Holidays", icon: "gift")
                }
            }
        }
    }

    private var statusSection: some View {
        findSection("Status", icon: "slider.horizontal.3", isClearVisible: isStatusActive, clear: clearStatus) {
            FlowLayout(spacing: 8) {
                chip("Favorites", icon: "heart", active: appState.library.searchFilter.favoritesOnly) {
                    appState.library.searchFilter.favoritesOnly.toggle()
                }
                disabledChip("Duplicate", icon: "doc.on.doc")
                chip("Trash", icon: "trash", active: appState.library.searchFilter.inTrash == true) {
                    appState.library.searchFilter.inTrash = appState.library.searchFilter.inTrash == true ? false : true
                }
            }
        }
    }

    private var sourceSection: some View {
        findSection("Source", icon: "camera", isClearVisible: isSourceActive, clear: clearDeviceSource) {
            FlowLayout(spacing: 8) {
                sourceChip(.phone, icon: "iphone")
                sourceChip(.pocket, icon: "camera.viewfinder")
                sourceChip(.actionCamera, icon: "figure.run")
                sourceChip(.drone, icon: "airplane")
                sourceChip(.camera, icon: "camera")
                sourceChip(.screenshot, icon: "rectangle.on.rectangle")
            }
        }
    }

    private var locationSection: some View {
        findSection("Location", icon: "mappin.and.ellipse", isClearVisible: false, clear: {}) {
            FlowLayout(spacing: 8) {
                disabledChip("Beijing", icon: "mappin")
                disabledChip("Shanghai", icon: "mappin")
                disabledChip("Japan", icon: "mappin")
                disabledChip("Trip", icon: "map")
            }
        }
    }

    private var peopleSection: some View {
        findSection("People", icon: "person", isClearVisible: false, clear: {}) {
            VStack(alignment: .leading, spacing: 8) {
                searchPlaceholder("Search people")
                FlowLayout(spacing: 8) {
                    disabledChip("People", icon: "person")
                    disabledChip("Family", icon: "person.2")
                    disabledChip("Friends", icon: "person.3")
                }
            }
        }
    }

    private var tagSection: some View {
        findSection("Tags", icon: "tag", isClearVisible: !appState.library.searchFilter.tagIDs.isEmpty) {
            appState.library.searchFilter.tagIDs = []
        } content: {
            if tagOptions.isEmpty {
                Text(appState.localized("No tags yet"))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(tagOptions) { option in
                        tagChip(option)
                    }
                }
            }
        }
        .task {
            tagOptions = await appState.library.topTags()
        }
    }

    private func tagChip(_ option: PhotoTagOption) -> some View {
        let active = appState.library.searchFilter.tagIDs.contains(option.id)
        return Button {
            if active {
                appState.library.searchFilter.tagIDs.remove(option.id)
            } else {
                appState.library.searchFilter.tagIDs.insert(option.id)
            }
        } label: {
            Text(option.displayName)
                .font(.callout)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(DesignSystem.Glass.activeTint) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Text(activeSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(.quaternary)
    }

    private func findSection<Content: View>(
        _ title: String,
        icon: String,
        isClearVisible: Bool,
        clear: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized(title), systemImage: icon)
                    .font(.callout.weight(.semibold))
                Spacer()
                if isClearVisible {
                    Button {
                        clear()
                    } label: {
                        Label(appState.localized("Clear"), systemImage: "xmark")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private func chip(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(appState.localized(title), systemImage: icon)
                .font(.callout)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(DesignSystem.Glass.activeTint) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dateChip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(appState.localized(title))
                .font(.callout)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(DesignSystem.Glass.activeTint) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dateRow<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 32)
            FlowLayout(spacing: 8) {
                content()
            }
        }
    }

    private func scoreDimensionChip(_ title: String, icon: String, active: Bool, enabled: Bool) -> some View {
        Label(appState.localized(title), systemImage: icon)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(scoreDimensionForeground(active: active, enabled: enabled))
            .background(active ? AnyShapeStyle(DesignSystem.Glass.activeTint) : AnyShapeStyle(.quaternary), in: Capsule())
    }

    private func segmentedOperator(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(appState.localized(title))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(active ? .white : .secondary)
                .background(active ? AnyShapeStyle(DesignSystem.Glass.activeTint) : AnyShapeStyle(.quaternary), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func scoreDimensionForeground(active: Bool, enabled: Bool) -> AnyShapeStyle {
        if active {
            return AnyShapeStyle(.white)
        }
        return enabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary)
    }

    private func disabledChip(_ title: String, icon: String) -> some View {
        Label(appState.localized(title), systemImage: icon)
            .font(.callout)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(.tertiary)
            .background(.quaternary, in: Capsule())
    }

    private func searchPlaceholder(_ placeholder: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            Text(appState.localized(placeholder))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func sourceChip(_ category: DeviceCategory, icon: String) -> some View {
        chip(sourceTitle(category), icon: icon, active: appState.library.searchFilter.deviceCategories.contains(category)) {
            if appState.library.searchFilter.deviceCategories.contains(category) {
                appState.library.searchFilter.deviceCategories.remove(category)
            } else {
                appState.library.searchFilter.deviceCategories.insert(category)
            }
            if category == .screenshot {
                appState.library.searchFilter.screenshotsOnly = appState.library.searchFilter.deviceCategories.contains(.screenshot)
                if appState.library.searchFilter.screenshotsOnly {
                    appState.library.searchFilter.mediaTypes = []
                }
            }
        }
    }

    private var countText: String {
        if appState.navigation.appLanguage == .zhHans || (appState.navigation.appLanguage == .system && Locale.preferredLanguages.first?.hasPrefix("zh") == true) {
            return "全部 \(appState.library.matchedPhotoCount.formatted()) 张"
        }
        return "\(appState.library.matchedPhotoCount.formatted()) matched"
    }

    private var activeSummary: String {
        let summary = filterSummary
        if summary.isEmpty {
            return appState.localized("No conditions summary")
        }
        return summary.joined(separator: " · ")
    }

    private var filterSummary: [String] {
        var parts: [String] = []
        let keyword = appState.library.searchFilter.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            parts.append("\"\(keyword)\"")
        }
        if isMediaActive {
            parts.append(appState.localized("Media Type"))
        }
        if isScoreActive {
            parts.append(scoreSummary)
        }
        if isTimeActive {
            parts.append(appState.localized("Time Range"))
        }
        if isStatusActive {
            parts.append(appState.localized("Status"))
        }
        if isSourceActive {
            parts.append(appState.localized("Source"))
        }
        return parts
    }

    private var scoreSummary: String {
        let score = Int(currentScoreValue.rounded())
        let op = scoreOperator == .greaterThan ? ">" : "<"
        return "\(appState.localized("Aesthetic"))\(op)\(score)"
    }

    private var scoreHint: String {
        let value = Int(currentScoreValue.rounded())
        if !isScoreActive {
            return appState.localized("Score filter inactive")
        }
        if scoreOperator == .greaterThan {
            return "\(appState.localized("Only show aesthetic greater than")) \(value)"
        }
        return "\(appState.localized("Only show aesthetic less than")) \(value)"
    }

    private var scoreOperator: ScoreOperator {
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

    private var scoreIntValue: Binding<Int> {
        Binding(
            get: { Int(currentScoreValue.rounded()) },
            set: { setScoreValue(Double($0)) }
        )
    }

    private var currentScoreValue: Double {
        appState.library.searchFilter.maximumAestheticScore ?? appState.library.searchFilter.minimumAestheticScore ?? 0
    }

    private var isMediaActive: Bool {
        !appState.library.searchFilter.mediaTypes.isEmpty || appState.library.searchFilter.screenshotsOnly
    }

    private var isScoreActive: Bool {
        appState.library.searchFilter.minimumAestheticScore != nil || appState.library.searchFilter.maximumAestheticScore != nil
    }

    private var isTimeActive: Bool {
        appState.library.searchFilter.createdAfter != nil || appState.library.searchFilter.createdBefore != nil
    }

    private var isStatusActive: Bool {
        appState.library.searchFilter.favoritesOnly || appState.library.searchFilter.inTrash == true
    }

    private var isSourceActive: Bool {
        !appState.library.searchFilter.deviceCategories.isEmpty
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

    private func toggleMediaType(_ mediaType: MediaType) {
        appState.library.searchFilter.screenshotsOnly = false
        if appState.library.searchFilter.mediaTypes.contains(mediaType) {
            appState.library.searchFilter.mediaTypes.remove(mediaType)
        } else {
            appState.library.searchFilter.mediaTypes.insert(mediaType)
        }
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
        appState.library.searchFilter.inTrash = false
    }

    private func clearDeviceSource() {
        appState.library.searchFilter.deviceCategories = []
        appState.library.searchFilter.screenshotsOnly = false
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

    private func setToday() {
        if isToday {
            clearTime()
            return
        }
        let start = Calendar.current.startOfDay(for: Date())
        appState.library.searchFilter.createdAfter = start
        appState.library.searchFilter.createdBefore = Calendar.current.date(byAdding: .day, value: 1, to: start)
    }

    private func setYesterday() {
        if isYesterday {
            clearTime()
            return
        }
        let today = Calendar.current.startOfDay(for: Date())
        guard let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today) else { return }
        appState.library.searchFilter.createdAfter = yesterday
        appState.library.searchFilter.createdBefore = today
    }

    private func setRecentDays(_ days: Int) {
        if isRecentDays(days) {
            clearTime()
            return
        }
        appState.library.searchFilter.createdAfter = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        appState.library.searchFilter.createdBefore = nil
    }

    private func setCurrentWeek() {
        setRangeMatchingToggle(active: isCurrentWeek) {
            let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
            return (interval?.start, interval?.end)
        }
    }

    private func setLastWeek() {
        setRangeMatchingToggle(active: isLastWeek) {
            guard
                let current = Calendar.current.dateInterval(of: .weekOfYear, for: Date()),
                let start = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: current.start),
                let end = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: current.end)
            else { return (nil, nil) }
            return (start, end)
        }
    }

    private func setCurrentMonth() {
        setRangeMatchingToggle(active: isCurrentMonth) {
            let interval = Calendar.current.dateInterval(of: .month, for: Date())
            return (interval?.start, interval?.end)
        }
    }

    private func setLastMonth() {
        setRangeMatchingToggle(active: isLastMonth) {
            guard
                let current = Calendar.current.dateInterval(of: .month, for: Date()),
                let start = Calendar.current.date(byAdding: .month, value: -1, to: current.start),
                let end = Calendar.current.date(byAdding: .month, value: -1, to: current.end)
            else { return (nil, nil) }
            return (start, end)
        }
    }

    private func setCurrentYear() {
        setRangeMatchingToggle(active: isCurrentYear) {
            let interval = Calendar.current.dateInterval(of: .year, for: Date())
            return (interval?.start, interval?.end)
        }
    }

    private func setLastYear() {
        setRangeMatchingToggle(active: isLastYear) {
            guard
                let current = Calendar.current.dateInterval(of: .year, for: Date()),
                let start = Calendar.current.date(byAdding: .year, value: -1, to: current.start),
                let end = Calendar.current.date(byAdding: .year, value: -1, to: current.end)
            else { return (nil, nil) }
            return (start, end)
        }
    }

    private func setRecentYears() {
        if isRecentYears {
            clearTime()
            return
        }
        appState.library.searchFilter.createdAfter = Calendar.current.date(byAdding: .year, value: -2, to: Date())
        appState.library.searchFilter.createdBefore = nil
    }

    private func setRangeMatchingToggle(active: Bool, range: () -> (Date?, Date?)) {
        if active {
            clearTime()
            return
        }
        let next = range()
        appState.library.searchFilter.createdAfter = next.0
        appState.library.searchFilter.createdBefore = next.1
    }

    private var isToday: Bool {
        let start = Calendar.current.startOfDay(for: Date())
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)
        return datesMatch(start: start, end: end)
    }

    private var isYesterday: Bool {
        let today = Calendar.current.startOfDay(for: Date())
        let start = Calendar.current.date(byAdding: .day, value: -1, to: today)
        return datesMatch(start: start, end: today)
    }

    private func isRecentDays(_ days: Int) -> Bool {
        guard let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let expected = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return abs(createdAfter.timeIntervalSince(expected)) < 8
            && appState.library.searchFilter.createdBefore == nil
    }

    private var isCurrentWeek: Bool {
        guard let interval = Calendar.current.dateInterval(of: .weekOfYear, for: Date()) else { return false }
        return datesMatch(start: interval.start, end: interval.end)
    }

    private var isLastWeek: Bool {
        guard
            let current = Calendar.current.dateInterval(of: .weekOfYear, for: Date()),
            let start = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: current.start),
            let end = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: current.end)
        else { return false }
        return datesMatch(start: start, end: end)
    }

    private var isCurrentMonth: Bool {
        guard let interval = Calendar.current.dateInterval(of: .month, for: Date()) else { return false }
        return datesMatch(start: interval.start, end: interval.end)
    }

    private var isLastMonth: Bool {
        guard
            let current = Calendar.current.dateInterval(of: .month, for: Date()),
            let start = Calendar.current.date(byAdding: .month, value: -1, to: current.start),
            let end = Calendar.current.date(byAdding: .month, value: -1, to: current.end)
        else { return false }
        return datesMatch(start: start, end: end)
    }

    private var isCurrentYear: Bool {
        guard let interval = Calendar.current.dateInterval(of: .year, for: Date()) else { return false }
        return datesMatch(start: interval.start, end: interval.end)
    }

    private var isLastYear: Bool {
        guard
            let current = Calendar.current.dateInterval(of: .year, for: Date()),
            let start = Calendar.current.date(byAdding: .year, value: -1, to: current.start),
            let end = Calendar.current.date(byAdding: .year, value: -1, to: current.end)
        else { return false }
        return datesMatch(start: start, end: end)
    }

    private var isRecentYears: Bool {
        guard let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let expected = Calendar.current.date(byAdding: .year, value: -2, to: Date()) ?? Date()
        return abs(createdAfter.timeIntervalSince(expected)) < 8
            && appState.library.searchFilter.createdBefore == nil
    }

    private func datesMatch(start: Date?, end: Date?) -> Bool {
        guard let start, let createdAfter = appState.library.searchFilter.createdAfter else { return false }
        let startMatches = abs(createdAfter.timeIntervalSince(start)) < 1
        switch (end, appState.library.searchFilter.createdBefore) {
        case (.none, .none):
            return startMatches
        case (.some(let lhs), .some(let rhs)):
            return startMatches && abs(lhs.timeIntervalSince(rhs)) < 1
        default:
            return false
        }
    }
}

private enum ScoreOperator {
    case greaterThan
    case lessThan
}
