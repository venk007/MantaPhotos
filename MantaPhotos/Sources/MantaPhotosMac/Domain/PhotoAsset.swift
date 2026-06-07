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
        isLocallyAvailable: Bool?
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
    }

    public var isScreenshot: Bool {
        (mediaSubtypesRawValue & PHAssetMediaSubtype.photoScreenshot.rawValue) != 0
    }
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
