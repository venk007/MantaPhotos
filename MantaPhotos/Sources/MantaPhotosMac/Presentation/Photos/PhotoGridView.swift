import AppKit
import Photos
import SwiftUI

struct PhotoGridView: NSViewControllerRepresentable {
    var items: [PhotoSearchResult]
    var gridLevel: GridLevel
    var badgeMetric: BadgeMetric
    var selectedIDs: Set<String>
    var sidebarExpanded: Bool
    var onSidebarExpandedChange: (Bool) -> Void
    var onLoadMore: () -> Void
    var onZoomStep: (Int) -> Void
    var onSelect: (PhotoSearchResult) -> Void

    func makeNSViewController(context: Context) -> PhotoGridViewController {
        let controller = PhotoGridViewController()
        controller.onSelect = onSelect
        controller.onSidebarExpandedChange = onSidebarExpandedChange
        controller.onLoadMore = onLoadMore
        controller.onZoomStep = onZoomStep
        return controller
    }

    func updateNSViewController(_ controller: PhotoGridViewController, context: Context) {
        controller.onSelect = onSelect
        controller.onSidebarExpandedChange = onSidebarExpandedChange
        controller.onLoadMore = onLoadMore
        controller.onZoomStep = onZoomStep
        controller.configure(
            items: items,
            gridLevel: gridLevel,
            badgeMetric: badgeMetric,
            selectedIDs: selectedIDs,
            sidebarExpanded: sidebarExpanded
        )
    }
}

final class PhotoGridViewController: NSViewController, NSCollectionViewDelegateFlowLayout {
    private var scrollView = NSScrollView()
    private var collectionView = NSCollectionView()
    private var flowLayout = NSCollectionViewFlowLayout()
    private var dataSource: NSCollectionViewDiffableDataSource<Int, String>?
    private var items: [PhotoSearchResult] = []
    private var itemByID: [String: PhotoSearchResult] = [:]
    private var gridLevel: GridLevel = .columns4
    private var badgeMetric: BadgeMetric = .aesthetic
    private var selectedIDs: Set<String> = []
    private var sidebarExpanded = true
    private var preheatedAssets: [String: PhotoAsset] = [:]
    private var preheatTargetSize: CGSize = .zero
    private var scrollBaselineY: CGFloat = 0
    private var sidebarHiddenByScroll = false
    private var sidebarWasExpandedBeforeScroll = false
    private var scrollRestoreWorkItem: DispatchWorkItem?
    private var magnificationAccumulator: CGFloat = 0
    private var didRequestLoadMoreAtCount = 0
    // 预热节流：记录上次重算预热时的滚动位置，并合并同一 runloop 内的多次滚动通知。
    private var lastPreheatOffsetY: CGFloat = .greatestFiniteMagnitude
    private var pendingPreheat = false
    var onSelect: ((PhotoSearchResult) -> Void)?
    var onSidebarExpandedChange: ((Bool) -> Void)?
    var onLoadMore: (() -> Void)?
    var onZoomStep: ((Int) -> Void)?

    deinit {
        NotificationCenter.default.removeObserver(self)
        MainActor.assumeIsolated {
            stopAllThumbnailPreheating()
        }
    }

    override func loadView() {
        view = NSView()

        flowLayout.minimumInteritemSpacing = 16
        flowLayout.minimumLineSpacing = 16
        // 底部预留出悬浮液态玻璃导航坞 + 状态条的空间，避免最后一行被遮挡。
        flowLayout.sectionInset = NSEdgeInsets(top: 16, left: 20, bottom: 96, right: 20)

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
        sidebarExpanded: Bool
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

        updateItemSize()
        if needsSnapshot {
            applySnapshot(animatingDifferences: false)
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
        flowLayout.itemSize = NSSize(width: size, height: size)
        flowLayout.invalidateLayout()
        stopAllThumbnailPreheating()
        refreshVisibleItems()
        updateThumbnailPreheating()
    }

    private func thumbnailTargetSize() -> CGSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let side = max(96, flowLayout.itemSize.width * scale)
        return CGSize(width: side, height: side)
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
                badgeMetric: self.badgeMetric,
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
                badgeMetric: badgeMetric,
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
        magnificationAccumulator += recognizer.magnification
        guard abs(magnificationAccumulator) >= 0.18 else { return }

        if magnificationAccumulator > 0 {
            onZoomStep?(-1)
        } else {
            onZoomStep?(1)
        }
        magnificationAccumulator = 0
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
    private let scoreLabel = NSTextField(labelWithString: "")
    private let mediaBadge = NSTextField(labelWithString: "")
    private let selectionRing = CALayer()
    private var thumbnailToken: ThumbnailRequestToken?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.masksToBounds = true
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor

        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.wantsLayer = true
        // 用图层 resizeAspectFill 等比填充并裁剪（方格内居中裁切），
        // 取代 NSImageView 的 scaleAxesIndependently 双轴拉伸，避免非方形照片畸变。
        thumbnailView.layer?.contentsGravity = .resizeAspectFill
        thumbnailView.layer?.masksToBounds = true

        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        scoreLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        scoreLabel.textColor = .white
        scoreLabel.alignment = .center
        scoreLabel.wantsLayer = true
        scoreLabel.layer?.cornerRadius = 10
        scoreLabel.layer?.masksToBounds = true

        mediaBadge.translatesAutoresizingMaskIntoConstraints = false
        mediaBadge.font = .systemFont(ofSize: 10, weight: .semibold)
        mediaBadge.textColor = .white
        mediaBadge.alignment = .center
        mediaBadge.wantsLayer = true
        mediaBadge.layer?.cornerRadius = 8
        mediaBadge.layer?.masksToBounds = true
        mediaBadge.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor

        selectionRing.borderWidth = 0
        selectionRing.borderColor = NSColor.controlAccentColor.cgColor
        selectionRing.cornerRadius = 12

        view.addSubview(thumbnailView)
        view.addSubview(scoreLabel)
        view.addSubview(mediaBadge)
        view.layer?.addSublayer(selectionRing)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: view.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            scoreLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scoreLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scoreLabel.heightAnchor.constraint(equalToConstant: 22),
            scoreLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42),

            mediaBadge.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            mediaBadge.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8),
            mediaBadge.heightAnchor.constraint(equalToConstant: 18),
            mediaBadge.widthAnchor.constraint(greaterThanOrEqualToConstant: 42)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        selectionRing.frame = view.bounds.insetBy(dx: 1.5, dy: 1.5)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        PhotoThumbnailProvider.shared.cancel(thumbnailToken)
        thumbnailToken = nil
        thumbnailView.layer?.contents = nil
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

        thumbnailToken = PhotoThumbnailProvider.shared.requestThumbnail(
            for: result.asset,
            targetSize: targetSize
        ) { [weak self] image in
            guard let self, self.representedObject as? String == result.id else { return }
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
            scoreLabel.isHidden = true
            return
        }

        scoreLabel.isHidden = false
        scoreLabel.stringValue = "\(Int(score.rounded()))"
        scoreLabel.layer?.backgroundColor = scoreColor(score).cgColor
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
