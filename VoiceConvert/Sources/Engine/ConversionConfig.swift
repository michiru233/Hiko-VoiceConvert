import Foundation

public enum VBRQuality: Int, CaseIterable, Identifiable, Codable, Sendable {
    case v0 = 0
    case v1 = 1
    case v2 = 2
    case v3 = 3
    case v4 = 4
    case v5 = 5
    case v6 = 6
    case v7 = 7
    case v8 = 8
    case v9 = 9

    public var id: Int { rawValue }

    public var displayName: String {
        switch self {
        case .v0: return "V0 (高保真 ~245 kbps)"
        case .v2: return "V2 (均衡推荐 ~190 kbps)"
        case .v4: return "V4 (省空间 ~165 kbps)"
        default: return "V\(rawValue)"
        }
    }
}

public enum QualityPreset: String, CaseIterable, Identifiable, Codable {
    case highFidelity = "highFidelity"  // V0
    case balanced = "balanced"          // V2
    case compact = "compact"            // V4
    case custom = "custom"

    public var id: String { rawValue }

    public var vbrQuality: VBRQuality {
        switch self {
        case .highFidelity: return .v0
        case .balanced: return .v2
        case .compact: return .v4
        case .custom: return .v2
        }
    }
}

public struct ConversionConfig: Codable, Equatable, Sendable {
    public var vbrQuality: VBRQuality
    public var fullStereo: Bool
    public var concurrency: Int
    public var deleteSourceOnSuccess: Bool
    public var outputDirectory: URL?

    public init(
        vbrQuality: VBRQuality = .v2,
        fullStereo: Bool = true,
        concurrency: Int = 4,
        deleteSourceOnSuccess: Bool = false,
        outputDirectory: URL? = nil
    ) {
        self.vbrQuality = vbrQuality
        self.fullStereo = fullStereo
        self.concurrency = max(1, min(8, concurrency))
        self.deleteSourceOnSuccess = deleteSourceOnSuccess
        self.outputDirectory = outputDirectory
    }
}
