import Foundation
import Testing
@testable import VoiceConvertCore

@Suite("UpdateCoreTests") struct UpdateCoreTests {
    @Test func parsesStrictTagsAndOrdersVersions() {
        #expect(SemanticVersion(tag: "v1.2.3") == SemanticVersion(major: 1, minor: 2, patch: 3))
        #expect(SemanticVersion(tag: "v1.2.3")! < SemanticVersion(major: 1, minor: 2, patch: 4))
        #expect(SemanticVersion(tag: "1.2.3") == nil)
        #expect(SemanticVersion(tag: "v1.2") == nil)
        #expect(SemanticVersion(tag: "v1.2.3-beta") == nil)
    }

    @Test func detectsOnlyNewerRelease() async throws {
        let service = GitHubReleaseService(loader: StubLoader(data: try releaseJSON(tag: "v1.1.2")), currentVersion: SemanticVersion(major: 1, minor: 1, patch: 1))
        guard case .updateAvailable(let release) = try await service.checkForUpdate() else {
            Issue.record("Expected update")
            return
        }
        #expect(release.version.description == "1.1.2")
        #expect(release.archiveURL.lastPathComponent == "Hiko-VoiceConvert-v1.1.2-macos-arm64.zip")
    }

    @Test func treatsSameAndOlderAsCurrent() async throws {
        for tag in ["v1.1.1", "v1.0.9"] {
            let service = GitHubReleaseService(loader: StubLoader(data: try releaseJSON(tag: tag)), currentVersion: SemanticVersion(major: 1, minor: 1, patch: 1))
            #expect(try await service.checkForUpdate() == .upToDate)
        }
    }

    @Test func rejectsMalformedDraftAndPrerelease() throws {
        #expect(throws: UpdateError.invalidRelease) { try GitHubReleaseService.parseRelease(from: try releaseJSON(tag: "v1.1")) }
        #expect(throws: UpdateError.invalidRelease) { try GitHubReleaseService.parseRelease(from: try releaseJSON(tag: "v1.1.2", draft: true)) }
        #expect(throws: UpdateError.invalidRelease) { try GitHubReleaseService.parseRelease(from: try releaseJSON(tag: "v1.1.2", prerelease: true)) }
    }

    @Test func rejectsMissingExactArm64Assets() throws {
        let data = try JSONSerialization.data(withJSONObject: ["tag_name": "v1.1.2", "html_url": "https://github.com/michiru233/Hiko-VoiceConvert/releases/tag/v1.1.2", "draft": false, "prerelease": false, "assets": [["name": "wrong.zip", "browser_download_url": "https://example.com/wrong.zip"]]])
        #expect(throws: UpdateError.missingArm64Assets) { try GitHubReleaseService.parseRelease(from: data) }
    }

    @Test func verifiesChecksumAndRejectsBadDigest() throws {
        let archive = Data("release contents".utf8)
        let checksum = Data("2225ba0ddddc17ea832336525669c34be0bc44f34fc5c1faafbc9984f5882b9f  Hiko-VoiceConvert-v1.1.2-macos-arm64.zip\n".utf8)
        try SHA256Verifier.verify(archiveData: archive, checksumFile: checksum, archiveName: "Hiko-VoiceConvert-v1.1.2-macos-arm64.zip")
        #expect(throws: UpdateError.checksumMismatch) {
            try SHA256Verifier.verify(archiveData: archive, checksumFile: Data("0000000000000000000000000000000000000000000000000000000000000000  Hiko-VoiceConvert-v1.1.2-macos-arm64.zip\n".utf8), archiveName: "Hiko-VoiceConvert-v1.1.2-macos-arm64.zip")
        }
        #expect(throws: UpdateError.invalidChecksum) { try SHA256Verifier.verify(archiveData: archive, checksumFile: Data("invalid".utf8), archiveName: "release.zip") }
    }

    @Test func rejectsUnsafeAndAmbiguousArchiveLayouts() throws {
        #expect(try UpdateArchiveLayout.applicationPath(in: ["root/App/音声转换.app/", "root/App/音声转换.app/Contents/Info.plist"]) == "root/App/音声转换.app")
        #expect(throws: UpdateError.malformedArchive) { try UpdateArchiveLayout.applicationPath(in: ["../escape/App/音声转换.app/"]) }
        #expect(throws: UpdateError.malformedArchive) { try UpdateArchiveLayout.applicationPath(in: ["one/App/音声转换.app/", "two/App/音声转换.app/"]) }
    }

    private func releaseJSON(tag: String, draft: Bool = false, prerelease: Bool = false) throws -> Data {
        let archive = "Hiko-VoiceConvert-\(tag)-macos-arm64.zip"
        return try JSONSerialization.data(withJSONObject: ["tag_name": tag, "html_url": "https://github.com/michiru233/Hiko-VoiceConvert/releases/tag/\(tag)", "draft": draft, "prerelease": prerelease, "assets": [["name": archive, "browser_download_url": "https://example.com/\(archive)"], ["name": "\(archive).sha256", "browser_download_url": "https://example.com/\(archive).sha256"]]])
    }
}

private struct StubLoader: UpdateDataLoading {
    let data: Data
    func data(from url: URL) async throws -> Data { data }
}
