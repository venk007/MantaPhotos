import CoreLocation
import Foundation
import Photos

public struct PhotoAsset: Identifiable, Equatable, Sendable {
    public var id: String
    public var localIdentifier: String
    public var filename: String?
    public var mediaType: MediaType
    public var mediaSubtypesRawValue: UInt
    public var creationDate: Date?
    public var modificationDate: Date?
    public var width: Int
    public var height: Int
    public var duration: TimeInterval?
    public var isFavorite: Bool
    public var isHidden: Bool
    public var inTrash: Bool
    public var trashedAt: Date?
    public var iCloudState: ICloudState
    public var isLocallyAvailable: Bool?

    // MARK: - 多照片源字段
    /// 所属照片源 id（系统图库为 `PhotoSourceDescriptor.systemPhotosID`）。
    public var sourceID: String
    /// 源内定位键：系统库为 `PHAsset.localIdentifier`，本地源为相对路径。
    public var sourceAssetKey: String
    /// 本地源：相对源根目录的路径（系统源为 nil）。
    public var relativePath: String?
    /// 本地源：内容指纹（用于跨源去重，可空）。
    public var contentHash: String?
    /// 本地源：文件大小（字节，可空）。
    public var fileSize: Int64?
    /// 是否截图：系统库由 mediaSubtypes 判定，本地源可在导入时显式置位。
    public var isScreenshotFlag: Bool

    public var pixelCount: Int { width * height }

    public init(
        id: String,
        localIdentifier: String,
        filename: String?,
        mediaType: MediaType,
        mediaSubtypesRawValue: UInt,
        creationDate: Date?,
        modificationDate: Date?,
        width: Int,
        height: Int,
        duration: TimeInterval?,
        isFavorite: Bool,
        isHidden: Bool,
        inTrash: Bool,
        trashedAt: Date?,
        iCloudState: ICloudState,
        isLocallyAvailable: Bool?,
        sourceID: String = PhotoAsset.systemPhotosSourceID,
        sourceAssetKey: String = "",
        relativePath: String? = nil,
        contentHash: String? = nil,
        fileSize: Int64? = nil,
        isScreenshotFlag: Bool = false
    ) {
        self.id = id
        self.localIdentifier = localIdentifier
        self.filename = filename
        self.mediaType = mediaType
        self.mediaSubtypesRawValue = mediaSubtypesRawValue
        self.creationDate = creationDate
        self.modificationDate = modificationDate
        self.width = width
        self.height = height
        self.duration = duration
        self.isFavorite = isFavorite
        self.isHidden = isHidden
        self.inTrash = inTrash
        self.trashedAt = trashedAt
        self.iCloudState = iCloudState
        self.isLocallyAvailable = isLocallyAvailable
        self.sourceID = sourceID
        self.sourceAssetKey = sourceAssetKey.isEmpty ? localIdentifier : sourceAssetKey
        self.relativePath = relativePath
        self.contentHash = contentHash
        self.fileSize = fileSize
        self.isScreenshotFlag = isScreenshotFlag
    }

    /// 系统图库源 id 常量（与 `PhotoSourceDescriptor.systemPhotosID` 一致，放这里避免循环引用）。
    public static let systemPhotosSourceID = "system_photos"

    public var isScreenshot: Bool {
        isScreenshotFlag || (mediaSubtypesRawValue & PHAssetMediaSubtype.photoScreenshot.rawValue) != 0
    }

    /// 是否系统图库资产。
    public var isSystemPhotos: Bool { sourceID == PhotoAsset.systemPhotosSourceID }
}

public enum MediaType: String, Codable, CaseIterable, Sendable, Identifiable {
    case image
    case video
    case livePhoto
    case unknown

    public var id: String { rawValue }

    init(phAssetMediaType: PHAssetMediaType, mediaSubtypes: PHAssetMediaSubtype) {
        switch phAssetMediaType {
        case .image where mediaSubtypes.contains(.photoLive):
            self = .livePhoto
        case .image:
            self = .image
        case .video:
            self = .video
        default:
            self = .unknown
        }
    }
}

public enum ICloudState: String, Codable, CaseIterable, Sendable {
    case unknown
    case local
    case remote
    case downloading
    case failed
}
