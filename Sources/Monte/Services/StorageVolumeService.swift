import Foundation

public struct MountedVolumeInfo: Identifiable, Sendable, Codable, Equatable {
    public var id: String { mountPath }
    public var name: String
    public var mountPath: String
    public var totalGb: Double
    public var freeGb: Double
    public var usedGb: Double { max(0, totalGb - freeGb) }
    public var usedPercent: Double { totalGb > 0 ? (usedGb / totalGb) * 100.0 : 0.0 }
    public var isInternal: Bool
    public var isRemovable: Bool
    public var fileSystemType: String

    public init(
        name: String,
        mountPath: String,
        totalGb: Double,
        freeGb: Double,
        isInternal: Bool,
        isRemovable: Bool,
        fileSystemType: String
    ) {
        self.name = name
        self.mountPath = mountPath
        self.totalGb = totalGb
        self.freeGb = freeGb
        self.isInternal = isInternal
        self.isRemovable = isRemovable
        self.fileSystemType = fileSystemType
    }
}

public final class StorageVolumeService: @unchecked Sendable {
    public static let shared = StorageVolumeService()
    private init() {}

    public func readVolumes() -> [MountedVolumeInfo] {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsInternalKey,
            .volumeIsRemovableKey,
            .volumeTypeNameKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            return []
        }

        var results: [MountedVolumeInfo] = []

        for url in urls {
            guard let vals = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let name = vals.volumeName ?? url.lastPathComponent
            let totalBytes = Double(vals.volumeTotalCapacity ?? 0)
            let freeBytes = Double(vals.volumeAvailableCapacity ?? 0)
            let isInternal = vals.volumeIsInternal ?? true
            let isRemovable = vals.volumeIsRemovable ?? false
            let fsType = vals.volumeTypeName ?? "APFS"

            let totalGb = totalBytes / 1_073_741_824.0
            let freeGb = freeBytes / 1_073_741_824.0

            guard totalGb > 0.5 else { continue }

            let path = url.path
            if path.contains("/System/Volumes/Update") || path.contains("/System/Volumes/VM") || path.contains("/System/Volumes/Preboot") {
                continue
            }

            let info = MountedVolumeInfo(
                name: name,
                mountPath: path,
                totalGb: totalGb,
                freeGb: freeGb,
                isInternal: isInternal,
                isRemovable: isRemovable,
                fileSystemType: fsType
            )
            results.append(info)
        }

        results.sort { v1, v2 in
            if v1.mountPath == "/" { return true }
            if v2.mountPath == "/" { return false }
            if v1.isInternal != v2.isInternal { return v1.isInternal }
            return v1.name.localizedStandardCompare(v2.name) == .orderedAscending
        }

        return results
    }
}
