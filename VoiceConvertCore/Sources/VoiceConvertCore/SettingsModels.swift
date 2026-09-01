import Foundation

public enum SettingsEncoding: String, Codable, CaseIterable, Sendable {
    case mp3
}

public enum SettingsSnapshotError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

/// The portable portion of user settings. Security-scoped bookmarks, history, and
/// in-flight tasks deliberately live outside this snapshot and cannot be imported.
public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public var vbrQuality: Int
    public var concurrency: Int
    public var outputDirectory: URL?
    public var deleteSourceOnSuccess: Bool
    public var encoding: SettingsEncoding
    public var strictMode: Bool
    public var cleanSubtitleText: Bool
    public var keepSpeakerPrefixes: Bool

    public init(
        schemaVersion: Int = SettingsSnapshot.currentSchemaVersion,
        vbrQuality: Int = 2,
        concurrency: Int = 4,
        outputDirectory: URL? = nil,
        deleteSourceOnSuccess: Bool = false,
        encoding: SettingsEncoding = .mp3,
        strictMode: Bool = false,
        cleanSubtitleText: Bool = true,
        keepSpeakerPrefixes: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.vbrQuality = Self.normalizedVBRQuality(vbrQuality)
        self.concurrency = Self.normalizedConcurrency(concurrency)
        self.outputDirectory = outputDirectory?.standardizedFileURL
        self.deleteSourceOnSuccess = deleteSourceOnSuccess
        self.encoding = encoding
        self.strictMode = strictMode
        self.cleanSubtitleText = cleanSubtitleText
        self.keepSpeakerPrefixes = keepSpeakerPrefixes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case vbrQuality
        case concurrency
        case outputDirectory
        case deleteSourceOnSuccess
        case encoding
        case strictMode
        case cleanSubtitleText
        case keepSpeakerPrefixes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard version <= Self.currentSchemaVersion else {
            throw SettingsSnapshotError.unsupportedSchemaVersion(version)
        }

        self.init(
            schemaVersion: Self.currentSchemaVersion,
            vbrQuality: try container.decodeIfPresent(Int.self, forKey: .vbrQuality) ?? 2,
            concurrency: try container.decodeIfPresent(Int.self, forKey: .concurrency) ?? 4,
            outputDirectory: try container.decodeIfPresent(URL.self, forKey: .outputDirectory),
            deleteSourceOnSuccess: try container.decodeIfPresent(Bool.self, forKey: .deleteSourceOnSuccess) ?? false,
            encoding: try container.decodeIfPresent(SettingsEncoding.self, forKey: .encoding) ?? .mp3,
            strictMode: try container.decodeIfPresent(Bool.self, forKey: .strictMode) ?? false,
            cleanSubtitleText: try container.decodeIfPresent(Bool.self, forKey: .cleanSubtitleText) ?? true,
            keepSpeakerPrefixes: try container.decodeIfPresent(Bool.self, forKey: .keepSpeakerPrefixes) ?? false
        )
    }

    private static func normalizedVBRQuality(_ value: Int) -> Int {
        min(9, max(0, value))
    }

    private static func normalizedConcurrency(_ value: Int) -> Int {
        min(8, max(1, value))
    }
}

public struct SecurityScopedBookmark: Codable, Equatable, Sendable {
    public let data: Data
    public let pathComponent: String

    public init(data: Data, pathComponent: String) {
        self.data = data
        self.pathComponent = URL(fileURLWithPath: pathComponent).lastPathComponent
    }

    public init(directory: URL) throws {
        self.init(
            data: try directory.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil),
            pathComponent: directory.standardizedFileURL.path
        )
    }

    public func resolve() throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        return (url.standardizedFileURL, stale)
    }

    public func startAccessing() throws -> URL {
        let resolved = try resolve()
        guard !resolved.isStale else { throw CocoaError(.fileReadCorruptFile) }
        guard resolved.url.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileReadNoPermission)
        }
        return resolved.url
    }

    public static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

public struct DiagnosticTaskSummary: Codable, Equatable, Sendable {
    public let role: String
    public let status: TaskStatus
    public let filename: String
    public let fileExtension: String

    public init(role: String, status: TaskStatus, filename: String) {
        self.role = role
        self.status = Self.redactedStatus(status)
        self.filename = URL(fileURLWithPath: filename).lastPathComponent
        self.fileExtension = URL(fileURLWithPath: filename).pathExtension.lowercased()
    }

    private static func redactedStatus(_ status: TaskStatus) -> TaskStatus {
        switch status {
        case .waiting, .running, .succeeded, .cancelled:
            return status
        case .succeededWithWarnings(let values):
            return .succeededWithWarnings(values.map(redact))
        case .skipped(let reason):
            return .skipped(redact(reason))
        case .failed(let reason):
            return .failed(redact(reason))
        }
    }

    private static func redact(_ value: String) -> String {
        value.split(separator: " ", omittingEmptySubsequences: false).map { token in
            let text = String(token)
            return text.hasPrefix("/") ? URL(fileURLWithPath: text).lastPathComponent : text
        }.joined(separator: " ")
    }
}

public struct DiagnosticReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let generatedAt: Date
    public let appVersion: String
    public let systemVersion: String
    public let architecture: String
    public let recentBatchCount: Int
    public let tasks: [DiagnosticTaskSummary]
    public let capabilities: [String]
    public let thirdPartyNotice: String

    public init(
        appVersion: String,
        systemVersion: String,
        architecture: String,
        recentBatchCount: Int,
        tasks: [DiagnosticTaskSummary],
        capabilities: [String],
        thirdPartyNotice: String
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = .now
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.architecture = architecture
        self.recentBatchCount = recentBatchCount
        self.tasks = tasks
        self.capabilities = capabilities
        self.thirdPartyNotice = thirdPartyNotice
    }

    public func encodedData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func save(to url: URL, fileManager: FileManager = .default) throws {
        let destination = url.standardizedFileURL
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encodedData().write(to: destination, options: .atomic)
    }

    public static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url.standardizedFileURL))
    }
}

public extension SettingsSnapshot {
    func save(to url: URL, fileManager: FileManager = .default) throws {
        let destination = url.standardizedFileURL
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: destination, options: .atomic)
    }

    static func load(from url: URL) throws -> Self {
        try JSONDecoder().decode(Self.self, from: Data(contentsOf: url.standardizedFileURL))
    }
}

/// State retained locally but intentionally excluded from a settings export/import.
public struct SettingsRuntimeState: Equatable, Sendable {
    public var preferences: SettingsSnapshot
    public var outputDirectoryBookmark: Data?
    public var recentBatches: RecentBatchStore
    public var runningTasks: [WorkflowTask]

    public init(
        preferences: SettingsSnapshot = SettingsSnapshot(),
        outputDirectoryBookmark: Data? = nil,
        recentBatches: RecentBatchStore = RecentBatchStore(),
        runningTasks: [WorkflowTask] = []
    ) {
        self.preferences = preferences
        self.outputDirectoryBookmark = outputDirectoryBookmark
        self.recentBatches = recentBatches
        self.runningTasks = runningTasks
    }
}

public enum SettingsImportPolicy {
    /// Imports only portable preferences. Local authorization, history, and active
    /// work stay attached to this installation.
    public static func apply(_ snapshot: SettingsSnapshot, to state: inout SettingsRuntimeState) {
        state.preferences = snapshot
    }
}

public enum RecentBatchStorePersistenceError: Error, Equatable, Sendable {
    case unreadable(path: String, reason: String)
    case migrationFailed(path: String, isolatedAt: String?, reason: String)
}

private struct RecentBatchStoreArchive: Codable {
    let schemaVersion: Int
    let batches: [BatchRecord]
}

public extension RecentBatchStore {
    /// Persists a versioned archive atomically. The archive schema is separate from
    /// individual batch schemas so its format can evolve without changing history.
    func save(to url: URL, fileManager: FileManager = .default) throws {
        let destination = url.standardizedFileURL
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let archive = RecentBatchStoreArchive(
            schemaVersion: Self.currentSchemaVersion,
            batches: batches
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: destination, options: .atomic)
    }

    /// Loads the current archive or upgrades the legacy unversioned `batches` file.
    /// A successful upgrade leaves a v0 backup beside the upgraded archive.
    static func load(from url: URL, fileManager: FileManager = .default) throws -> Self {
        let source = url.standardizedFileURL
        guard fileManager.fileExists(atPath: source.path) else { return Self() }

        let data: Data
        do {
            data = try Data(contentsOf: source)
        } catch {
            throw RecentBatchStorePersistenceError.unreadable(path: source.path, reason: error.localizedDescription)
        }

        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let document = object as? [String: Any] else {
                throw MigrationError.invalidDocument
            }

            if let version = document["schemaVersion"] as? Int {
                guard version <= Self.currentSchemaVersion else {
                    throw MigrationError.unsupportedSchema(version)
                }
                if version == Self.currentSchemaVersion {
                    let archive = try JSONDecoder().decode(RecentBatchStoreArchive.self, from: data)
                    return Self(batches: archive.batches)
                }
                return try migrate(data: data, from: version, source: source, fileManager: fileManager)
            }

            return try migrate(data: data, from: 0, source: source, fileManager: fileManager)
        } catch {
            let isolated = isolate(source, fileManager: fileManager)
            throw RecentBatchStorePersistenceError.migrationFailed(
                path: source.path,
                isolatedAt: isolated?.path,
                reason: error.localizedDescription
            )
        }
    }

    static func upgradeBackupURL(for url: URL, legacySchemaVersion: Int) -> URL {
        url.standardizedFileURL.appendingPathExtension("v\(legacySchemaVersion).backup")
    }

    private enum MigrationError: LocalizedError {
        case invalidDocument
        case unsupportedSchema(Int)

        var errorDescription: String? {
            switch self {
            case .invalidDocument:
                return "批次历史文件不是有效的 JSON 对象"
            case let .unsupportedSchema(version):
                return "不支持的批次历史版本 \(version)"
            }
        }
    }

    private static func migrate(
        data: Data,
        from version: Int,
        source: URL,
        fileManager: FileManager
    ) throws -> Self {
        guard version == 0 else { throw MigrationError.unsupportedSchema(version) }

        let legacy = try JSONDecoder().decode(LegacyArchive.self, from: data)
        let backup = upgradeBackupURL(for: source, legacySchemaVersion: version)
        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }
        try fileManager.copyItem(at: source, to: backup)

        let migrated = Self(batches: legacy.batches)
        try migrated.save(to: source, fileManager: fileManager)
        return migrated
    }

    private static func isolate(_ source: URL, fileManager: FileManager) -> URL? {
        let isolated = source.deletingLastPathComponent().appendingPathComponent(
            "\(source.lastPathComponent).migration-failed-\(UUID().uuidString)"
        )
        do {
            try fileManager.moveItem(at: source, to: isolated)
            return isolated
        } catch {
            return nil
        }
    }
}

private struct LegacyArchive: Decodable {
    let batches: [BatchRecord]
}
