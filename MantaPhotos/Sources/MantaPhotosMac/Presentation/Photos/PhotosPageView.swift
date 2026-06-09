import SwiftUI

struct PhotosPageView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var library = appState.library
        VStack(spacing: 0) {
            PhotosToolbarView()
            if !appState.library.searchFilter.isEmpty {
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
                        }
                    )
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
        .sheet(isPresented: $library.isViewerPresented) {
            if let result = appState.library.selectedPhotoForViewer {
                PhotoViewerView(result: result)
                    .environment(appState)
            }
        }
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
        .padding(.vertical, 8)
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
        if filter.inTrash == true {
            parts.append("trash")
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
            }
            .disabled(currentIndex >= GridLevel.allCases.count - 1)
            .help(appState.localized("Zoom out"))

            Text("\(appState.navigation.gridLevel.rawValue)")
                .font(.caption.monospacedDigit())
                .frame(width: 28)

            Button {
                appState.navigation.adjustGridLevel(step: -1)
            } label: {
                Image(systemName: "plus")
            }
            .disabled(currentIndex <= 0)
            .help(appState.localized("Zoom in"))
        }
        .buttonStyle(.borderless)
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var currentIndex: Int {
        GridLevel.allCases.firstIndex(of: appState.navigation.gridLevel) ?? 1
    }
}

struct BadgeSegmentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 2) {
            segment(.aesthetic, icon: "camera.aperture")
            segment(.overall, icon: "star")
        }
        .padding(3)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func segment(_ metric: BadgeMetric, icon: String) -> some View {
        Button {
            appState.navigation.badgeMetric = appState.navigation.badgeMetric == metric ? .hidden : metric
        } label: {
            Label(appState.localized(metric.localizationKey), systemImage: icon)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(appState.navigation.badgeMetric == metric ? .white : .secondary)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(.clear)
                .overlay {
                    if appState.navigation.badgeMetric == metric {
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.control)
                            .fill(DesignSystem.Glass.activeTint)
                    }
                }
        }
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
