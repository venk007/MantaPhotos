import AppKit
import Photos
import SwiftUI

/// 年/月滚动导航的一个分组：某个月在结果中第一张照片的位置。
struct GridDateSection: Identifiable, Equatable, Sendable {
    var id: String          // "yyyy-MM"
    var date: Date          // 该月起始（用于展示与排序）
    var firstIndex: Int     // 该月第一张照片在结果数组里的下标
    var year: Int
    var month: Int
}

struct PhotoGridView: NSViewControllerRepresentable {
    var items: [PhotoSearchResult]
    var gridLevel: GridLevel
    var badgeMetric: BadgeMetric
    var selectedIDs: Set<String>
    var sidebarExpanded: Bool
    /// 顶部内容预留空间：为悬浮液态玻璃工具栏 / 横幅腾出位置，避免第一行照片
    /// 初始状态就被浮在最上层的玻璃条遮住。
    var topContentInset: CGFloat = 8
    var onSidebarExpandedChange: (Bool) -> Void
    var onLoadMore: () -> Void
    var onZoomStep: (Int) -> Void
    var onSelect: (PhotoSearchResult) -> Void
    var onSectionsChange: ([GridDateSection]) -> Void = { _ in }
    var onVisibleDateChange: (Date?) -> Void = { _ in }
    /// 由滚动导航请求跳转到的下标；处理后通过 onScrollHandled 复位。
    var scrollToIndex: Int?
    var onScrollHandled: () -> Void = {}

    func makeNSViewController(context: Context) -> PhotoGridViewController {
        let controller = PhotoGridViewController()
        applyCallbacks(to: controller)
        return controller
    }

    func updateNSViewController(_ controller: PhotoGridViewController, context: Context) {
        applyCallbacks(to: controller)
        controller.configure(
            items: items,
            gridLevel: gridLevel,
            badgeMetric: badgeMetric,
            selectedIDs: selectedIDs,
            sidebarExpanded: sidebarExpanded,
            topContentInset: topContentInset
        )
        if let scrollToIndex {
            controller.scrollToItem(index: scrollToIndex)
            let handler = onScrollHandled
            DispatchQueue.main.async { handler() }
        }
    }

    private func applyCallbacks(to controller: PhotoGridViewController) {
        controller.onSelect = onSelect
        controller.onSidebarExpandedChange = onSidebarExpandedChange
        controller.onLoadMore = onLoadMore
        controller.onZoomStep = onZoomStep
        controller.onSectionsChange = onSectionsChange
        controller.onVisibleDateChange = onVisibleDateChange
    }
}

final class PhotoGridViewController: NSViewController, NSCollectionViewDelegateFlowLayout {
    private var scrollView = NSScrollView()
    private var collectionView = NSCollectionView()
    private var flowLayout = NSCollectionViewFlowLayout()
    private var dataSource: NSCollectionViewDiffableDataSource<Int, String>?
    private var items: [PhotoSearchResult] = []
    private var itemByID: [String: PhotoSearchResult] = [:]
    private var gridLevel: GridLevel = .default
    private var badgeMetric: BadgeMetric = .aesthetic
    private var selectedIDs: Set<String> = []
    private var sidebarExpanded = true
    private var preheatedAssets: [String: PhotoAsset] = [:]
    private var preheatTargetSize: CGSize = .zero
    private var scrollBaselineY: CGFloat = 0
    private var sidebarHiddenByScroll = false
    private var sidebarWasExpandedBeforeScroll = false
    private var scrollRestoreWorkItem: DispatchWorkItem?
    private var didZoomStepThisGesture = false
    private var didRequestLoadMoreAtCount = 0
    // 预热节流：记录上次重算预热时的滚动位置，并合并同一 runloop 内的多次滚动通知。
    private var lastPreheatOffsetY: CGFloat = .greatestFiniteMagnitude
    private var pendingPreheat = false
    private var lastReportedVisibleIndex = -1
    var onSelect: ((PhotoSearchResult) -> Void)?
    var onSidebarExpandedChange: ((Bool) -> Void)?
    var onLoadMore: (() -> Void)?
    var onZoomStep: ((Int) -> Void)?
    var onSectionsChange: (([GridDateSection]) -> Void)?
    var onVisibleDateChange: ((Date?) -> Void)?

    deinit {
        NotificationCenter.default.removeObserver(self)
        MainActor.assumeIsolated {
            stopAllThumbnailPreheating()
        }
    }

    override func loadView() {
        view = NSView()

        flowLayout.minimumInteritemSpacing = 2
        flowLayout.minimumLineSpacing = 2
        // 底部预留出悬浮液态玻璃导航坞 + 状态条的空间，避免最后一行被遮挡。
        flowLayout.sectionInset = NSEdgeInsets(top: 8, left: 12, bottom: 96, right: 12)

        collectionView.collectionViewLayout = flowLayout
        collectionView.delegate = self
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(PhotoGridItem.self, forItemWithIdentifier: PhotoGridItem.identifier)
        dataSource = makeDataSource()
        let magnificationRecognizer = NSMagnificationGestureRecognizer(
            target: self,
            action: #selector(handleMagnification(_:))
        )
        collectionView.addGestureRecognizer(magnificationRecognizer)

        scrollView.documentView = collectionView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollViewBoundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        updateItemSize()
        updateThumbnailPreheating()
    }

    func configure(
        items: [PhotoSearchResult],
        gridLevel: GridLevel,
        badgeMetric: BadgeMetric,
        selectedIDs: Set<String>,
        sidebarExpanded: Bool,
        topContentInset: CGFloat = 8
    ) {
        let oldIDs = self.items.map(\.id)
        let newIDs = items.map(\.id)
        let needsSnapshot = oldIDs != newIDs
        let needsVisibleRefresh = self.items != items
            || self.badgeMetric != badgeMetric
            || self.selectedIDs != selectedIDs

        self.items = items
        self.itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        self.gridLevel = gridLevel
        self.badgeMetric = badgeMetric
        self.selectedIDs = selectedIDs
        self.sidebarExpanded = sidebarExpanded

        if flowLayout.sectionInset.top != topContentInset {
            flowLayout.sectionInset.top = topContentInset
            flowLayout.invalidateLayout()
        }

        updateItemSize()
        if needsSnapshot {
            applySnapshot(animatingDifferences: false)
            recomputeDateSections()
        } else if needsVisibleRefresh {
            refreshVisibleItems()
            updateThumbnailPreheating()
        }
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard let index = indexPaths.first?.item, items.indices.contains(index) else { return }
        onSelect?(items[index])
    }

    func collectionView(
        _ collectionView: NSCollectionView,
        layout collectionViewLayout: NSCollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> NSSize {
        flowLayout.itemSize
    }

    private func updateItemSize() {
        let columns = CGFloat(gridLevel.columnCount)
        let inset = flowLayout.sectionInset.left + flowLayout.sectionInset.right
        let spacing = flowLayout.minimumInteritemSpacing * max(0, columns - 1)
        let available = max(160, collectionView.bounds.width - inset - spacing)
        let width = floor(available / columns)
        let size = max(34, width)
        guard flowLayout.itemSize.width != size else { return }

        stopAllThumbnailPreheating()

        // 网格密度切换动画：贴近系统照片 App 的缩放过渡——单元格平滑过渡到新尺寸并
        // 重新排布，而不是瞬间跳变。`NSAnimationContext` + `collectionView.animator()`
        // 让 flowLayout 的尺寸变化在下一次布局中以隐式动画呈现；时长与缓动曲线刻意
        // 保持克制（0.22s、easeInEaseOut），流畅但不拖沓，避免视觉眩晕。
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            flowLayout.itemSize = NSSize(width: size, height: size)
            flowLayout.invalidateLayout()
            collectionView.animator().performBatchUpdates(nil, completionHandler: nil)
        }

        refreshVisibleItems()
        updateThumbnailPreheating()
    }

    private func thumbnailTargetSize() -> CGSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let side = max(96, flowLayout.itemSize.width * scale)
        return CGSize(width: side, height: side)
    }

    /// 列数 ≥ 15 时强制不显示分数角标（密度优先）。
    private var effectiveBadgeMetric: BadgeMetric {
        gridLevel.columnCount >= 15 ? .hidden : badgeMetric
    }

    private func makeDataSource() -> NSCollectionViewDiffableDataSource<Int, String> {
        NSCollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, id in
            let item = collectionView.makeItem(
                withIdentifier: PhotoGridItem.identifier,
                for: indexPath
            )

            guard
                let self,
                let gridItem = item as? PhotoGridItem,
                let result = self.itemByID[id]
            else { return item }

            gridItem.configure(
                result: result,
                badgeMetric: self.effectiveBadgeMetric,
                selected: self.selectedIDs.contains(result.id),
                targetSize: self.thumbnailTargetSize()
            )
            return gridItem
        }
    }

    private func applySnapshot(animatingDifferences: Bool) {
        guard let dataSource else { return }
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(items.map(\.id), toSection: 0)
        dataSource.apply(snapshot, animatingDifferences: animatingDifferences) { [weak self] in
            self?.refreshVisibleItems()
            self?.updateThumbnailPreheating()
        }
    }

    private func refreshVisibleItems() {
        for indexPath in collectionView.indexPathsForVisibleItems() {
            guard
                items.indices.contains(indexPath.item),
                let gridItem = collectionView.item(at: indexPath) as? PhotoGridItem
            else { continue }
            let result = items[indexPath.item]
            gridItem.configure(
                result: result,
                badgeMetric: effectiveBadgeMetric,
                selected: selectedIDs.contains(result.id),
                targetSize: thumbnailTargetSize()
            )
        }
    }

    @objc
    private func scrollViewBoundsDidChange() {
        updateSidebarForScroll()
        updateLoadMoreTrigger()
        schedulePreheatUpdate()
        reportVisibleDate()
    }

    // MARK: - 年/月滚动导航

    private func recomputeDateSections() {
        var sections: [GridDateSection] = []
        var seen = Set<String>()
        let calendar = Calendar.current
        for (index, item) in items.enumerated() {
            guard let date = item.asset.creationDate else { continue }
            let comps = calendar.dateComponents([.year, .month], from: date)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = "\(year)-\(month)"
            if seen.insert(key).inserted {
                let monthStart = calendar.date(from: DateComponents(year: year, month: month)) ?? date
                sections.append(
                    GridDateSection(id: key, date: monthStart, firstIndex: index, year: year, month: month)
                )
            }
        }
        onSectionsChange?(sections)
    }

    private func reportVisibleDate() {
        guard !items.isEmpty else { return }
        let topIndex = collectionView.indexPathsForVisibleItems()
            .map(\.item)
            .filter { items.indices.contains($0) }
            .min() ?? 0
        guard topIndex != lastReportedVisibleIndex else { return }
        lastReportedVisibleIndex = topIndex
        onVisibleDateChange?(items[topIndex].asset.creationDate)
    }

    func scrollToItem(index: Int) {
        guard items.indices.contains(index) else { return }
        collectionView.scrollToItems(
            at: [IndexPath(item: index, section: 0)],
            scrollPosition: .top
        )
    }

    /// 滚动时的预热调度：滚动距离不足半行不重算，且把同一 runloop 内的多次通知合并为一次，
    /// 避免每个滚动帧都做一次布局属性查询造成卡顿。
    private func schedulePreheatUpdate() {
        let currentY = scrollView.contentView.bounds.origin.y
        let threshold = max(40, flowLayout.itemSize.height * 0.5)
        guard abs(currentY - lastPreheatOffsetY) >= threshold else { return }
        guard !pendingPreheat else { return }
        pendingPreheat = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingPreheat = false
            self.updateThumbnailPreheating()
        }
    }

    @objc
    private func handleMagnification(_ recognizer: NSMagnificationGestureRecognizer) {
        // 每个捏合手势只调一个档位：手势开始重置，跨过阈值后调一次并锁定，手势结束再解锁。
        // `recognizer.magnification` 是自手势开始以来的累计值。
        switch recognizer.state {
        case .began:
            didZoomStepThisGesture = false
        case .changed:
            guard !didZoomStepThisGesture else { return }
            let magnification = recognizer.magnification
            if magnification >= 0.25 {
                didZoomStepThisGesture = true
                onZoomStep?(-1) // 张开 = 放大 = 更少列
            } else if magnification <= -0.25 {
                didZoomStepThisGesture = true
                onZoomStep?(1)  // 捏合 = 缩小 = 更多列
            }
        default:
            didZoomStepThisGesture = false
        }
    }

    private func updateThumbnailPreheating() {
        guard !items.isEmpty, flowLayout.itemSize.width > 0 else {
            stopAllThumbnailPreheating()
            return
        }

        // 记录基线，供滚动节流判断；不再每帧强制 layoutSubtreeIfNeeded（flow 布局属性按需可得）。
        lastPreheatOffsetY = scrollView.contentView.bounds.origin.y
        let visibleRect = scrollView.contentView.bounds
        let preheatRect = visibleRect.insetBy(dx: 0, dy: -visibleRect.height * 0.75)
        let assetsInRect = assetsForItems(in: preheatRect)
        let nextByID = Dictionary(assetsInRect.map { ($0.id, $0) }, uniquingKeysWith: { lhs, _ in lhs })
        let nextIDs = Set(nextByID.keys)
        let currentIDs = Set(preheatedAssets.keys)
        let targetSize = thumbnailTargetSize()

        if preheatTargetSize != .zero, preheatTargetSize != targetSize {
            PhotoThumbnailProvider.shared.stopCaching(
                assets: Array(preheatedAssets.values),
                targetSize: preheatTargetSize
            )
            preheatedAssets = [:]
        }

        let addedIDs = nextIDs.subtracting(currentIDs)
        let removedIDs = currentIDs.subtracting(nextIDs)

        if !removedIDs.isEmpty {
            let removedAssets = removedIDs.compactMap { preheatedAssets[$0] }
            PhotoThumbnailProvider.shared.stopCaching(
                assets: removedAssets,
                targetSize: preheatTargetSize == .zero ? targetSize : preheatTargetSize
            )
        }

        if !addedIDs.isEmpty {
            let addedAssets = addedIDs.compactMap { nextByID[$0] }
            PhotoThumbnailProvider.shared.startCaching(
                assets: addedAssets,
                targetSize: targetSize
            )
        }

        preheatedAssets = nextByID
        preheatTargetSize = targetSize
    }

    private func stopAllThumbnailPreheating() {
        guard !preheatedAssets.isEmpty else { return }
        PhotoThumbnailProvider.shared.stopCaching(
            assets: Array(preheatedAssets.values),
            targetSize: preheatTargetSize == .zero ? thumbnailTargetSize() : preheatTargetSize
        )
        preheatedAssets = [:]
        preheatTargetSize = .zero
    }

    private func assetsForItems(in rect: NSRect) -> [PhotoAsset] {
        let attributes = collectionView.collectionViewLayout?.layoutAttributesForElements(in: rect) ?? []
        let indexes = attributes
            .compactMap { $0.indexPath?.item }
            .filter { items.indices.contains($0) }

        if indexes.isEmpty {
            return collectionView.indexPathsForVisibleItems()
                .map(\.item)
                .filter { items.indices.contains($0) }
                .map { items[$0].asset }
        }

        return indexes.map { items[$0].asset }
    }

    private func updateSidebarForScroll() {
        let currentY = scrollView.contentView.bounds.origin.y
        if abs(currentY - scrollBaselineY) >= 10 {
            scrollBaselineY = currentY
            if sidebarExpanded, !sidebarHiddenByScroll {
                sidebarWasExpandedBeforeScroll = true
                sidebarHiddenByScroll = true
                sidebarExpanded = false
                onSidebarExpandedChange?(false)
            }
        }

        scrollRestoreWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scrollBaselineY = self.scrollView.contentView.bounds.origin.y
            if self.sidebarHiddenByScroll, self.sidebarWasExpandedBeforeScroll, !self.sidebarExpanded {
                self.sidebarHiddenByScroll = false
                self.sidebarWasExpandedBeforeScroll = false
                self.sidebarExpanded = true
                self.onSidebarExpandedChange?(true)
            } else {
                self.sidebarHiddenByScroll = false
                self.sidebarWasExpandedBeforeScroll = false
            }
        }
        scrollRestoreWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
    }

    private func updateLoadMoreTrigger() {
        guard !items.isEmpty else { return }

        let visibleRect = scrollView.contentView.bounds
        let contentHeight = collectionView.bounds.height
        let distanceToBottom = contentHeight - visibleRect.maxY
        guard distanceToBottom < max(visibleRect.height * 1.5, 600) else { return }
        guard didRequestLoadMoreAtCount != items.count else { return }

        didRequestLoadMoreAtCount = items.count
        onLoadMore?()
    }
}

final class PhotoGridItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("PhotoGridItem")

    private let thumbnailView = NSView()
    private let scoreBadge = NSVisualEffectView()
    private let scoreGradient = CAGradientLayer()
    private let scoreLabel = NSTextField(labelWithString: "")
    private let mediaBadge = NSTextField(labelWithString: "")
    private let similarityLabel = NSTextField(labelWithString: "")
    /// 「相似照片」结果中，基准照片本身的角标（右下角，与 `similarityLabel` 互斥）。
    private let referenceBadge = NSTextField(labelWithString: "")
    private let selectionRing = CALayer()
    private var thumbnailToken: ThumbnailRequestToken?
    /// 每次 `configure()`/`prepareForReuse()` 自增的请求世代号。
    ///
    /// 用于在缩略图完成回调里区分"当前请求"与"过期请求"：闭包捕获发起时的
    /// `generation` 值，回调时与 `self.requestGeneration` 比较——只有相等
    /// 才应用结果。比直接捕获 `ThumbnailRequestToken` 引用更简单
    /// （避免"闭包在其自身声明之前捕获 token"的编译错误），效果等价。
    private var requestGeneration = 0

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 0
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.wantsLayer = true
        // 用图层 resizeAspectFill 等比填充并裁剪（方格内居中裁切），
        // 取代 NSImageView 的 scaleAxesIndependently 双轴拉伸，避免非方形照片畸变。
        thumbnailView.layer?.contentsGravity = .resizeAspectFill
        thumbnailView.layer?.masksToBounds = true

        // 评分角标：液态玻璃底（系统材质模糊 + 半透明）+ 分数区间色的左→右渐变叠色；
        // 文字用约束在玻璃容器内水平/垂直双向居中，不再依赖文本框自身背景。
        scoreBadge.translatesAutoresizingMaskIntoConstraints = false
        scoreBadge.material = .hudWindow
        scoreBadge.blendingMode = .withinWindow
        scoreBadge.state = .active
        scoreBadge.wantsLayer = true
        scoreBadge.layer?.cornerRadius = 11
        scoreBadge.layer?.masksToBounds = true
        scoreBadge.layer?.addSublayer(scoreGradient)
        scoreGradient.startPoint = CGPoint(x: 0, y: 0.5)
        scoreGradient.endPoint = CGPoint(x: 1, y: 0.5)

        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        scoreLabel.textColor = .white
        scoreLabel.alignment = .center
        scoreLabel.drawsBackground = false

        mediaBadge.translatesAutoresizingMaskIntoConstraints = false
        mediaBadge.font = .systemFont(ofSize: 10, weight: .semibold)
        mediaBadge.textColor = .white
        mediaBadge.alignment = .center
        mediaBadge.wantsLayer = true
        mediaBadge.layer?.cornerRadius = 8
        mediaBadge.layer?.masksToBounds = true
        mediaBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor

        // 「相似照片」结果的相似度角标：右下角，仅相似模式下有值时显示。
        similarityLabel.translatesAutoresizingMaskIntoConstraints = false
        similarityLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        similarityLabel.textColor = .white
        similarityLabel.alignment = .center
        similarityLabel.wantsLayer = true
        similarityLabel.layer?.cornerRadius = 8
        similarityLabel.layer?.masksToBounds = true
        similarityLabel.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.78).cgColor
        similarityLabel.isHidden = true

        // 「原图」角标：与 similarityLabel 同位置、同尺寸，标记相似照片结果中的基准照片本身。
        // 用一颗实心星星 + 文案，外观上与相似度角标区分（中性深色而非强调色），
        // 含义是「这是查找的起点」而非「与起点的相似度」。
        referenceBadge.translatesAutoresizingMaskIntoConstraints = false
        referenceBadge.stringValue = "★ 原图"
        referenceBadge.font = .systemFont(ofSize: 11, weight: .semibold)
        referenceBadge.textColor = .white
        referenceBadge.alignment = .center
        referenceBadge.wantsLayer = true
        referenceBadge.layer?.cornerRadius = 8
        referenceBadge.layer?.masksToBounds = true
        referenceBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.55).cgColor
        referenceBadge.isHidden = true

        selectionRing.borderWidth = 0
        selectionRing.borderColor = NSColor.controlAccentColor.cgColor
        selectionRing.cornerRadius = 0

        view.addSubview(thumbnailView)
        view.addSubview(scoreBadge)
        scoreBadge.addSubview(scoreLabel)
        view.addSubview(mediaBadge)
        view.addSubview(similarityLabel)
        view.addSubview(referenceBadge)
        view.layer?.addSublayer(selectionRing)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scoreBadge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scoreBadge.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scoreBadge.heightAnchor.constraint(equalToConstant: 22),
            scoreBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),

            // 文字在玻璃容器内水平 + 垂直双向居中；两侧留出最小内边距防止贴边。
            scoreLabel.centerXAnchor.constraint(equalTo: scoreBadge.centerXAnchor),
            scoreLabel.centerYAnchor.constraint(equalTo: scoreBadge.centerYAnchor),
            scoreLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scoreBadge.leadingAnchor, constant: 6),
            scoreLabel.trailingAnchor.constraint(lessThanOrEqualTo: scoreBadge.trailingAnchor, constant: -6),

            mediaBadge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mediaBadge.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            mediaBadge.heightAnchor.constraint(equalToConstant: 18),
            mediaBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),

            similarityLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            similarityLabel.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            similarityLabel.heightAnchor.constraint(equalToConstant: 20),
            similarityLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),

            referenceBadge.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            referenceBadge.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            referenceBadge.heightAnchor.constraint(equalToConstant: 20),
            referenceBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        selectionRing.frame = view.bounds.insetBy(dx: 1.5, dy: 1.5)
        scoreGradient.frame = scoreBadge.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        PhotoThumbnailProvider.shared.cancel(thumbnailToken)
        thumbnailToken = nil
        // 使任何仍在途的旧请求回调失效（见 `requestGeneration` 文档注释）。
        requestGeneration += 1
        thumbnailView.layer?.contents = nil
        similarityLabel.isHidden = true
        referenceBadge.isHidden = true
        representedObject = nil
    }

    func configure(
        result: PhotoSearchResult,
        badgeMetric: BadgeMetric,
        selected: Bool,
        targetSize: CGSize
    ) {
        representedObject = result.id
        thumbnailView.layer?.contents = nil
        selectionRing.borderWidth = selected ? 3 : 0

        configureScore(result: result, badgeMetric: badgeMetric)
        configureMediaBadge(result.asset.mediaType)
        configureSimilarity(result: result)

        // 「缩略图偶尔不清晰」的一个根因：`.opportunistic` 投递会先回调一张
        // 「降质」预览图、稍后再回调最终高质量图；如果本 cell 在最终图到达前
        // 被 `prepareForReuse()` 回收（快速滚动）又复用为同一个 `result.id`
        // （滚回原位），旧请求的「降质图」回调可能在新请求之后才到达——
        // 仅靠 `representedObject == result.id` 无法区分新旧请求，旧的降质图
        // 会覆盖新请求已经设置好的清晰图。
        //
        // 这里额外比较闭包捕获的世代号 `generation` 与 `self.requestGeneration`
        // （见该属性的文档注释）：只有「当前」请求的回调才会通过这个判断，
        // 被取消/被替换的旧请求回调直接丢弃。
        requestGeneration += 1
        let generation = requestGeneration
        thumbnailToken = PhotoThumbnailProvider.shared.requestThumbnail(
            for: result.asset,
            targetSize: targetSize
        ) { [weak self] image in
            guard let self,
                  self.representedObject as? String == result.id,
                  self.requestGeneration == generation else { return }
            self.setThumbnail(image)
        }
    }

    /// 把缩略图作为图层内容（CGImage）写入，配合 `resizeAspectFill` 等比裁剪填充，不拉伸。
    private func setThumbnail(_ image: NSImage?) {
        guard let image else {
            thumbnailView.layer?.contents = nil
            return
        }
        var proposedRect = CGRect(origin: .zero, size: image.size)
        thumbnailView.layer?.contents = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }

    private func configureScore(result: PhotoSearchResult, badgeMetric: BadgeMetric) {
        let score: Double?
        switch badgeMetric {
        case .aesthetic:
            score = result.aestheticScore
        case .overall:
            score = result.overallScore
        case .hidden:
            score = nil
        }

        guard let score else {
            scoreBadge.isHidden = true
            return
        }

        scoreBadge.isHidden = false
        scoreLabel.stringValue = "\(Int(score.rounded()))"
        // 主题色按分数区间保持不变（仍由 scoreColor 决定色相）；
        // 渐变仅在左右两端使用不同透明度，呈现液态玻璃的半透明 + 渐变质感。
        let tint = scoreColor(score)
        scoreGradient.colors = [
            tint.withAlphaComponent(0.85).cgColor,
            tint.withAlphaComponent(0.32).cgColor
        ]
    }

    /// 「相似照片」右下角角标：基准照片本身显示「★ 原图」，其余结果显示与基准的相似度百分比；
    /// 非相似模式下两者皆隐藏。两者位置重叠、互斥显示。
    private func configureSimilarity(result: PhotoSearchResult) {
        if result.isReferencePhoto {
            referenceBadge.isHidden = false
            similarityLabel.isHidden = true
            return
        }
        referenceBadge.isHidden = true

        guard let score = result.similarityScore else {
            similarityLabel.isHidden = true
            return
        }
        similarityLabel.isHidden = false
        let percent = Int((score * 100).rounded())
        similarityLabel.stringValue = "\(percent)%"
    }

    private func configureMediaBadge(_ mediaType: MediaType) {
        switch mediaType {
        case .video:
            mediaBadge.stringValue = "VIDEO"
            mediaBadge.isHidden = false
        case .livePhoto:
            mediaBadge.stringValue = "LIVE"
            mediaBadge.isHidden = false
        case .unknown:
            mediaBadge.stringValue = "MEDIA"
            mediaBadge.isHidden = false
        case .image:
            mediaBadge.isHidden = true
        }
    }

    private func scoreColor(_ score: Double) -> NSColor {
        switch score {
        case 80...100:
            NSColor(calibratedRed: 0.42, green: 0.63, blue: 0.86, alpha: 0.72)
        case 60..<80:
            NSColor(calibratedRed: 0.40, green: 0.76, blue: 0.58, alpha: 0.72)
        case 40..<60:
            NSColor(calibratedRed: 0.91, green: 0.77, blue: 0.34, alpha: 0.74)
        default:
            NSColor(calibratedRed: 0.91, green: 0.55, blue: 0.62, alpha: 0.76)
        }
    }
}
