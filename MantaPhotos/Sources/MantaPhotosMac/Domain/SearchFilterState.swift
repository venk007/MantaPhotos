import Foundation
import Photos
import SwiftUI

public struct SearchFilterState: Equatable, Codable, Sendable {
    public var keyword: String = ""
    public var mediaTypes: Set<MediaType> = []
    public var screenshotsOnly: Bool = false
    public var minimumAestheticScore: Double?
    public var maximumAestheticScore: Double?
    public var createdAfter: Date?
    public var createdBefore: Date?
    public var favoritesOnly: Bool = false
    public var includeHidden: Bool = false
    public var inTrash: Bool? = false
    public var iCloudStates: Set<ICloudState> = []
    public var deviceCategories: Set<DeviceCategory> = []
    public var tagIDs: Set<String> = []
    public var locationNames: Set<String> = []
    public var personIDs: Set<String> = []
    public var sortMode: SortMode = .creationDateDescending

    public init() {}

    public var isEmpty: Bool {
        keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mediaTypes.isEmpty
            && !screenshotsOnly
            && minimumAestheticScore == nil
            && maximumAestheticScore == nil
            && createdAfter == nil
            && createdBefore == nil
            && !favoritesOnly
            && !includeHidden
            && inTrash == false
            && iCloudStates.isEmpty
            && deviceCategories.isEmpty
            && tagIDs.isEmpty
            && locationNames.isEmpty
            && personIDs.isEmpty
    }

    public func makeSQLSelection() -> SQLSelection {
        var clauses: [String] = ["photo_assets.system_deleted_at is null"]
        var arguments: [SQLValue] = []

        if !mediaTypes.isEmpty {
            clauses.append("photo_assets.media_type in (\(Self.placeholders(count: mediaTypes.count)))")
            arguments.append(contentsOf: mediaTypes.map { .text($0.rawValue) })
        }

        if screenshotsOnly {
            clauses.append("(photo_assets.media_subtypes_raw & ?) != 0")
            arguments.append(.int(Int(PHAssetMediaSubtype.photoScreenshot.rawValue)))
        }

        if let minimumAestheticScore {
            clauses.append("photo_scores.aesthetic_score >= ?")
            arguments.append(.double(minimumAestheticScore))
        }

        if let maximumAestheticScore {
            clauses.append("photo_scores.aesthetic_score <= ?")
            arguments.append(.double(maximumAestheticScore))
        }

        if let createdAfter {
            clauses.append("photo_assets.creation_date >= ?")
            arguments.append(.text(Self.format(date: createdAfter)))
        }

        if let createdBefore {
            clauses.append("photo_assets.creation_date <= ?")
            arguments.append(.text(Self.format(date: createdBefore)))
        }

        if favoritesOnly {
            clauses.append("photo_assets.is_favorite = 1")
        }

        if !includeHidden {
            clauses.append("photo_assets.is_hidden = 0")
        }

        if let inTrash {
            clauses.append("photo_assets.in_trash = ?")
            arguments.append(.int(inTrash ? 1 : 0))
        }

        if !iCloudStates.isEmpty {
            clauses.append("photo_assets.icloud_state in (\(Self.placeholders(count: iCloudStates.count)))")
            arguments.append(contentsOf: iCloudStates.map { .text($0.rawValue) })
        }

        if !deviceCategories.isEmpty {
            clauses.append("photo_assets.device_category in (\(Self.placeholders(count: deviceCategories.count)))")
            arguments.append(contentsOf: deviceCategories.map { .text($0.rawValue) })
        }

        if !tagIDs.isEmpty {
            clauses.append(
                """
                exists (
                  select 1 from photo_tags
                  where photo_tags.photo_id = photo_assets.id
                    and photo_tags.tag_id in (\(Self.placeholders(count: tagIDs.count)))
                )
                """
            )
            arguments.append(contentsOf: tagIDs.map { .text($0) })
        }

        if !locationNames.isEmpty {
            clauses.append(
                """
                exists (
                  select 1 from photo_locations
                  where photo_locations.photo_id = photo_assets.id
                    and photo_locations.locality in (\(Self.placeholders(count: locationNames.count)))
                )
                """
            )
            arguments.append(contentsOf: locationNames.map { .text($0) })
        }

        if !personIDs.isEmpty {
            clauses.append(
                """
                exists (
                  select 1 from photo_people
                  where photo_people.photo_id = photo_assets.id
                    and photo_people.person_id in (\(Self.placeholders(count: personIDs.count)))
                )
                """
            )
            arguments.append(contentsOf: personIDs.map { .text($0) })
        }

        return SQLSelection(
            whereClause: clauses.isEmpty ? "1 = 1" : clauses.joined(separator: " and "),
            arguments: arguments,
            orderBy: sortMode.orderByClause
        )
    }

    private static func placeholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func format(date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// 评分筛选的完整文案，用于全局查找浮层。
    ///
    /// 规则（与重构前一致）：
    /// - 最低分为 0 且最高分小于 100 → "搜索小于 N 分数的照片"
    /// - 最低分大于 0 且最高分为 100 → "搜索大于 N 分数的照片"
    /// - 最低分大于 0 且最高分小于 100 → "搜索 A 到 B 分数的照片"
    /// - 两端都未设置 → 未启用评分筛选，返回 `nil`
    public func scoreFilterSummary(localizer: (String) -> String) -> String? {
        let hasMin = (minimumAestheticScore ?? 0) > 0
        let hasMax = (maximumAestheticScore ?? 100) < 100
        let lower = Int((minimumAestheticScore ?? 0).rounded())
        let upper = Int((maximumAestheticScore ?? 100).rounded())

        switch (hasMin, hasMax) {
        case (false, false):
            return nil
        case (false, true):
            return String(format: localizer("Score Filter Below Format"), upper)
        case (true, false):
            return String(format: localizer("Score Filter Above Format"), lower)
        case (true, true):
            return String(format: localizer("Score Filter Range Format"), lower, upper)
        }
    }

    /// 高分照片阈值：与四档评分配色的最高档下限保持一致。
    public static let highScoreThreshold: Double = 80
    /// 低分照片阈值：与四档评分配色的最低档上限保持一致。
    public static let lowScoreThreshold: Double = 40

    /// “高分照片”快捷筛选是否处于激活状态。
    public var isHighScoreQuickFilterActive: Bool {
        minimumAestheticScore == Self.highScoreThreshold && maximumAestheticScore == nil
    }

    /// “低分照片”快捷筛选是否处于激活状态。
    public var isLowScoreQuickFilterActive: Bool {
        maximumAestheticScore == Self.lowScoreThreshold && minimumAestheticScore == nil
    }

    /// 切换“高分照片”快捷筛选：单选语义，再次点击即清空。
    public mutating func toggleHighScoreQuickFilter() {
        if isHighScoreQuickFilterActive {
            minimumAestheticScore = nil
        } else {
            minimumAestheticScore = Self.highScoreThreshold
            maximumAestheticScore = nil
        }
    }

    /// 切换“低分照片”快捷筛选：单选语义，再次点击即清空。
    public mutating func toggleLowScoreQuickFilter() {
        if isLowScoreQuickFilterActive {
            maximumAestheticScore = nil
        } else {
            maximumAestheticScore = Self.lowScoreThreshold
            minimumAestheticScore = nil
        }
    }

    /// 评分筛选的极简文案（≤12 个汉字），用于侧栏快捷筛选标签，逻辑与 `scoreFilterSummary` 一致。
    public func scoreFilterSummaryCompact(localizer: (String) -> String) -> String? {
        let hasMin = (minimumAestheticScore ?? 0) > 0
        let hasMax = (maximumAestheticScore ?? 100) < 100
        let lower = Int((minimumAestheticScore ?? 0).rounded())
        let upper = Int((maximumAestheticScore ?? 100).rounded())

        switch (hasMin, hasMax) {
        case (false, false):
            return nil
        case (false, true):
            return String(format: localizer("Score Filter Below Compact"), upper)
        case (true, false):
            return String(format: localizer("Score Filter Above Compact"), lower)
        case (true, true):
            return String(format: localizer("Score Filter Range Compact"), lower, upper)
        }
    }
}

public enum DeviceCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case phone
    case pocket
    case actionCamera = "action_camera"
    case drone
    case camera
    case screenshot
    case unknown

    public var id: String { rawValue }

    public var displayName: LocalizedStringKey {
        switch self {
        case .phone: "Device Phone"
        case .pocket: "Device Pocket"
        case .actionCamera: "Device Action Camera"
        case .drone: "Device Drone"
        case .camera: "Device SLR Camera"
        case .screenshot: "Device Screenshot"
        case .unknown: "Device Unknown"
        }
    }
}

public enum SortMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case creationDateDescending
    case creationDateAscending
    case aestheticScoreDescending
    case aestheticScoreAscending

    public var id: String { rawValue }

    public var orderByClause: String {
        switch self {
        case .creationDateDescending:
            "photo_assets.creation_date desc nulls last, photo_assets.id"
        case .creationDateAscending:
            "photo_assets.creation_date asc nulls last, photo_assets.id"
        case .aestheticScoreDescending:
            "photo_scores.aesthetic_score desc nulls last, photo_assets.creation_date desc nulls last"
        case .aestheticScoreAscending:
            "photo_scores.aesthetic_score asc nulls last, photo_assets.creation_date desc nulls last"
        }
    }

    public var displayName: LocalizedStringKey {
        switch self {
        case .creationDateDescending: "Sort Newest"
        case .creationDateAscending: "Sort Oldest"
        case .aestheticScoreDescending: "Sort Score High"
        case .aestheticScoreAscending: "Sort Score Low"
        }
    }

    public var localizationKey: String {
        switch self {
        case .creationDateDescending: "Sort Newest"
        case .creationDateAscending: "Sort Oldest"
        case .aestheticScoreDescending: "Sort Score High"
        case .aestheticScoreAscending: "Sort Score Low"
        }
    }
}

public struct SQLSelection: Equatable, Sendable {
    public var whereClause: String
    public var arguments: [SQLValue]
    public var orderBy: String
}

public enum SQLValue: Equatable, Sendable {
    case int(Int)
    case double(Double)
    case text(String)
    case null
}
