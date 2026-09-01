import XCTest
import Foundation

final class AppSettingsControllerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var root: URL!

    override func setUpWithError() throws {
        defaultsSuiteName = "AppSettingsControllerTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)!
        root = FileManager.default.temporaryDirectory.appendingPathComponent("app-settings-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    func testBookmarkPersistsResolvesAndCanBeCleared() throws {
        let directory = root.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bookmark = try AppSettingsController.bookmark(from: directory)
        try AppSettingsController.saveBookmark(bookmark, defaults: defaults)
        let loaded = try XCTUnwrap(AppSettingsController.loadBookmark(defaults: defaults))
        XCTAssertEqual(loaded.pathComponent, directory.lastPathComponent)
        XCTAssertEqual(try AppSettingsController.resolveBookmark(loaded), directory.standardizedFileURL)
        try AppSettingsController.saveBookmark(nil, defaults: defaults)
        XCTAssertNil(try AppSettingsController.loadBookmark(defaults: defaults))
    }

    func testInvalidBookmarkIsRejected() throws {
        let invalid = SecurityScopedBookmark(data: Data("invalid".utf8), pathComponent: "/tmp/output")
        XCTAssertThrowsError(try AppSettingsController.resolveBookmark(invalid))
    }

    func testSettingsImportRoundTripDoesNotIncludeBookmarkOrHistory() throws {
        let settingsFile = root.appendingPathComponent("settings.json")
        let snapshot = SettingsSnapshot(vbrQuality: 4, concurrency: 2, outputDirectory: root.appendingPathComponent("chosen"), strictMode: true, keepSpeakerPrefixes: true)
        try AppSettingsController.exportSettings(snapshot, to: settingsFile)
        let imported = try AppSettingsController.importSettings(from: settingsFile)
        XCTAssertEqual(imported, snapshot)
        let json = String(decoding: try Data(contentsOf: settingsFile), as: UTF8.self)
        XCTAssertFalse(json.contains("outputDirectoryBookmark"))
        XCTAssertFalse(json.contains("recentBatches"))
        XCTAssertFalse(json.contains("runningTasks"))
    }

    func testDiagnosticReportRedactsAbsolutePathAndRoundTrips() throws {
        let task = WorkflowTask(inputURL: URL(fileURLWithPath: "/Users/private/record.wav"), status: .failed("/Users/private/record.wav"))
        let report = AppSettingsController.diagnosticReport(appVersion: "1.1.0", recentBatchCount: 1, tasks: [task])
        let file = root.appendingPathComponent("diagnostic.json")
        try report.save(to: file)
        let json = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertFalse(json.contains("/Users/private"))
        XCTAssertTrue(json.contains("record.wav"))
        XCTAssertEqual(try DiagnosticReport.load(from: file), report)
    }
}
