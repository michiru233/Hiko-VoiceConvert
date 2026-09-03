import CryptoKit
import Foundation

public enum UpdateConfiguration {
    public static let productName = "音声转换"
    public static let bundleIdentifier = "com.voiceconvert.app"
    public static let currentVersionString = "1.1.2"
    public static let currentVersion = SemanticVersion(tag: "v\(currentVersionString)")!
    public static let repository = "michiru233/Hiko-VoiceConvert"
    public static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
}

public struct SemanticVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init?(tag: String) {
        let parts = tag.split(separator: ".", omittingEmptySubsequences: false)
        guard tag.first == "v", parts.count == 3,
              let major = Int(parts[0].dropFirst()),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]), major >= 0, minor >= 0, patch >= 0 else { return nil }
        self.init(major: major, minor: minor, patch: patch)
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

public struct UpdateRelease: Equatable, Sendable {
    public let version: SemanticVersion
    public let releasePageURL: URL
    public let archiveURL: URL
    public let checksumURL: URL

    public init(version: SemanticVersion, releasePageURL: URL, archiveURL: URL, checksumURL: URL) {
        self.version = version
        self.releasePageURL = releasePageURL
        self.archiveURL = archiveURL
        self.checksumURL = checksumURL
    }
}

public enum UpdateDiscoveryResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(UpdateRelease)
}

public enum UpdateError: Error, Equatable, LocalizedError, Sendable {
    case invalidRelease
    case missingArm64Assets
    case invalidChecksum
    case checksumMismatch
    case malformedArchive
    case unsupportedInstallation
    case invalidApplication
    case codeSignatureInvalid
    case helperUnavailable

    public var errorDescription: String? {
        switch self {
        case .invalidRelease: return "GitHub 返回的版本信息无效。"
        case .missingArm64Assets: return "该版本没有可用的 macOS arm64 安装包。"
        case .invalidChecksum: return "发布包的校验文件无效。"
        case .checksumMismatch: return "下载文件未通过 SHA-256 完整性校验。"
        case .malformedArchive: return "安装包结构不安全或不完整。"
        case .unsupportedInstallation: return "当前应用位置不可自动安装，请前往发布页手动下载。"
        case .invalidApplication: return "安装包中的应用标识或版本不匹配。"
        case .codeSignatureInvalid: return "安装包未通过代码签名校验。"
        case .helperUnavailable: return "更新安装组件不可用，请前往发布页手动下载。"
        }
    }
}

public protocol UpdateDataLoading: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionUpdateDataLoader: UpdateDataLoading {
    public init() {}

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Hiko-VoiceConvert/\(UpdateConfiguration.currentVersionString)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else {
            throw UpdateError.invalidRelease
        }
        return data
    }
}

public struct GitHubReleaseService: Sendable {
    private let loader: any UpdateDataLoading
    private let currentVersion: SemanticVersion

    public init(loader: any UpdateDataLoading = URLSessionUpdateDataLoader(), currentVersion: SemanticVersion = UpdateConfiguration.currentVersion) {
        self.loader = loader
        self.currentVersion = currentVersion
    }

    public func checkForUpdate() async throws -> UpdateDiscoveryResult {
        let release = try Self.parseRelease(from: await loader.data(from: UpdateConfiguration.latestReleaseURL))
        return release.version > currentVersion ? .updateAvailable(release) : .upToDate
    }

    public static func parseRelease(from data: Data) throws -> UpdateRelease {
        let response: GitHubReleaseResponse
        do {
            response = try JSONDecoder().decode(GitHubReleaseResponse.self, from: data)
        } catch {
            throw UpdateError.invalidRelease
        }
        guard !response.draft, !response.prerelease,
              let version = SemanticVersion(tag: response.tagName),
              let releasePageURL = URL(string: response.htmlURL) else { throw UpdateError.invalidRelease }

        let archiveName = "Hiko-VoiceConvert-v\(version)-macos-arm64.zip"
        guard let archive = response.assets.first(where: { $0.name == archiveName }),
              let checksum = response.assets.first(where: { $0.name == "\(archiveName).sha256" }),
              let archiveURL = URL(string: archive.browserDownloadURL),
              let checksumURL = URL(string: checksum.browserDownloadURL) else { throw UpdateError.missingArm64Assets }
        return UpdateRelease(version: version, releasePageURL: releasePageURL, archiveURL: archiveURL, checksumURL: checksumURL)
    }

    private struct GitHubReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease, assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}

public enum SHA256Verifier {
    public static func expectedDigest(from checksumFile: Data, for archiveName: String) throws -> String {
        guard let text = String(data: checksumFile, encoding: .utf8) else { throw UpdateError.invalidChecksum }
        let escapedName = NSRegularExpression.escapedPattern(for: archiveName)
        let regex = try NSRegularExpression(pattern: "^([A-Fa-f0-9]{64})\\s+\\*?\(escapedName)\\s*$", options: [.anchorsMatchLines])
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { throw UpdateError.invalidChecksum }
        return String(text[range]).lowercased()
    }

    public static func verify(archiveData: Data, checksumFile: Data, archiveName: String) throws {
        let expected = try expectedDigest(from: checksumFile, for: archiveName)
        let actual = SHA256.hash(data: archiveData).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch }
    }
}

public enum UpdateArchiveLayout {
    public static func applicationPath(in entries: [String]) throws -> String {
        guard !entries.isEmpty, entries.allSatisfy({ entry in
            !entry.hasPrefix("/") && !entry.split(separator: "/").contains("..") && !entry.contains("\0")
        }) else { throw UpdateError.malformedArchive }
        let suffix = "/App/\(UpdateConfiguration.productName).app/"
        let candidates = entries.filter { $0.hasSuffix(suffix) }
        guard candidates.count == 1, let path = candidates.first else { throw UpdateError.malformedArchive }
        return String(path.dropLast())
    }
}
