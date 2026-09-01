import Foundation
import Testing
@testable import VoiceConvertCore

struct SettingsModelsTests {
    private func tempDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("settings-models-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func batch(named inputName: String = "input.wav") -> BatchRecord {
        BatchRecord(tasks: [
            WorkflowTask(inputURL: URL(fileURLWithPath: "/tmp/\(inputName)"), status: .succeeded)
        ])
    }

    @Test func settingsSnapshotRoundTripsAllPortablePreferences() throws {
        let directory = URL(fileURLWithPath: "/tmp/voice-output/../output")
        let snapshot = SettingsSnapshot(
            vbrQuality: 7,
            concurrency: 6,
            outputDirectory: directory,
            deleteSourceOnSuccess: true,
            encoding: .mp3,
            strictMode: true,
            cleanSubtitleText: false,
            keepSpeakerPrefixes: true
        )

        let decoded = try JSONDecoder().decode(
            SettingsSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        #expect(decoded == snapshot)
        #expect(decoded.schemaVersion == SettingsSnapshot.currentSchemaVersion)
        #expect(decoded.outputDirectory == directory.standardizedFileURL)
    }

    @Test func settingsSnapshotMigratesVersionZeroAndNormalizesValues() throws {
        let legacy = """
        {
          "vbrQuality": 42,
          "concurrency": 0,
          "outputDirectory": "file:///tmp/old-output",
          "deleteSourceOnSuccess": true
        }
        """

        let snapshot = try JSONDecoder().decode(SettingsSnapshot.self, from: Data(legacy.utf8))

        #expect(snapshot.schemaVersion == SettingsSnapshot.currentSchemaVersion)
        #expect(snapshot.vbrQuality == 9)
        #expect(snapshot.concurrency == 1)
        #expect(snapshot.outputDirectory == URL(fileURLWithPath: "/tmp/old-output"))
        #expect(snapshot.deleteSourceOnSuccess)
        #expect(snapshot.encoding == .mp3)
        #expect(!snapshot.strictMode)
        #expect(snapshot.cleanSubtitleText)
        #expect(!snapshot.keepSpeakerPrefixes)
    }

    @Test func settingsSnapshotRejectsNewerSchema() throws {
        let newer = """
        { "schemaVersion": 2 }
        """

        #expect(throws: SettingsSnapshotError.unsupportedSchemaVersion(2)) {
            try JSONDecoder().decode(SettingsSnapshot.self, from: Data(newer.utf8))
        }
    }

    @Test func settingsImportOnlyReplacesPortablePreferences() {
        let imported = SettingsSnapshot(vbrQuality: 0, concurrency: 8, strictMode: true)
        let originalBatch = batch(named: "history.wav")
        let runningTask = WorkflowTask(inputURL: URL(fileURLWithPath: "/tmp/running.wav"), status: .running)
        var state = SettingsRuntimeState(
            preferences: SettingsSnapshot(vbrQuality: 9),
            outputDirectoryBookmark: Data([1, 2, 3]),
            recentBatches: RecentBatchStore(batches: [originalBatch]),
            runningTasks: [runningTask]
        )

        SettingsImportPolicy.apply(imported, to: &state)

        #expect(state.preferences == imported)
        #expect(state.outputDirectoryBookmark == Data([1, 2, 3]))
        #expect(state.recentBatches == RecentBatchStore(batches: [originalBatch]))
        #expect(state.runningTasks == [runningTask])
    }

    @Test func settingsSnapshotFileRoundTripIsVersionedAndAtomic() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        let expected = SettingsSnapshot(vbrQuality: 4, concurrency: 3, outputDirectory: directory.appendingPathComponent("out"), strictMode: true)
        try expected.save(to: file)
        let actual = try SettingsSnapshot.load(from: file)
        #expect(actual == expected)
        #expect(String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("schemaVersion"))
    }

    @Test func settingsSnapshotFileRejectsCorruptDocumentThenAcceptsRecovery() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("settings.json")
        try Data("not-json".utf8).write(to: file)
        #expect(throws: Error.self) { try SettingsSnapshot.load(from: file) }
        let recovered = SettingsSnapshot(vbrQuality: 1, concurrency: 2, strictMode: true)
        try recovered.save(to: file)
        #expect(try SettingsSnapshot.load(from: file) == recovered)
    }
    @Test func securityScopedBookmarkRoundTripsWithoutExposingFullPathInMetadata() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bookmark = try SecurityScopedBookmark(directory: directory)
        #expect(bookmark.pathComponent == directory.lastPathComponent)
        #expect(!String(decoding: try JSONEncoder().encode(bookmark), as: UTF8.self).contains(directory.deletingLastPathComponent().path))
        let resolved = try bookmark.resolve()
        #expect(resolved.url.standardizedFileURL == directory.standardizedFileURL)
        SecurityScopedBookmark.stopAccessing(resolved.url)
    }

    @Test func diagnosticReportRoundTripsAndRedactsUserPathAndBookmarkData() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let task = DiagnosticTaskSummary(role: "audio", status: .failed("/Users/private/audio.wav"), filename: "/Users/private/audio.wav")
        let report = DiagnosticReport(appVersion: "1.1.0", systemVersion: "macOS", architecture: "arm64", recentBatchCount: 2,
                                      tasks: [task], capabilities: ["audio-mp3"], thirdPartyNotice: "ThirdParty/licenses")
        let data = try report.encodedData()
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("/Users/private"))
        #expect(json.contains("audio.wav"))
        let decoded = try JSONDecoder().decode(DiagnosticReport.self, from: data)
        #expect(decoded == report)
        let file = directory.appendingPathComponent("diagnostic.json")
        try report.save(to: file)
        #expect(try DiagnosticReport.load(from: file) == report)
    }

    @Test func recentBatchStoreSavesAndLoadsCurrentArchive() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recent-batches.json")
        let expected = RecentBatchStore(batches: [batch(named: "one.wav"), batch(named: "two.wav")])

        try expected.save(to: file)
        let actual = try RecentBatchStore.load(from: file)
        let document = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]

        #expect(actual == expected)
        #expect(document?["schemaVersion"] as? Int == RecentBatchStore.currentSchemaVersion)
    }

    @Test func recentBatchStoreUpgradesLegacyArchiveAndKeepsBackup() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recent-batches.json")
        let expected = RecentBatchStore(batches: [batch(named: "legacy.wav")])
        let legacyData = try JSONEncoder().encode(expected)
        try legacyData.write(to: file)

        let migrated = try RecentBatchStore.load(from: file)
        let backup = RecentBatchStore.upgradeBackupURL(for: file, legacySchemaVersion: 0)
        let backupData = try Data(contentsOf: backup)
        let upgradedDocument = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any]

        #expect(migrated == expected)
        #expect(backupData == legacyData)
        #expect(upgradedDocument?["schemaVersion"] as? Int == RecentBatchStore.currentSchemaVersion)
    }

    @Test func recentBatchStoreIsolatesMigrationFailure() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("recent-batches.json")
        try Data("not json".utf8).write(to: file)

        do {
            _ = try RecentBatchStore.load(from: file)
            Issue.record("期望迁移失败")
        } catch let RecentBatchStorePersistenceError.migrationFailed(path, isolatedAt, _) {
            #expect(path == file.standardizedFileURL.path)
            #expect(isolatedAt != nil)
            #expect(!FileManager.default.fileExists(atPath: file.path))
            #expect(isolatedAt.map { FileManager.default.fileExists(atPath: $0) } == true)
        }
    }
}
