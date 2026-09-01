import Foundation

struct AppSettingsController {
    static let bookmarkDefaultsKey = "VoiceConvert.OutputDirectoryBookmark"

    static func bookmark(from directory: URL) throws -> SecurityScopedBookmark {
        try SecurityScopedBookmark(directory: directory)
    }

    static func saveBookmark(_ bookmark: SecurityScopedBookmark?, defaults: UserDefaults = .standard) throws {
        if let bookmark {
            defaults.set(try JSONEncoder().encode(bookmark), forKey: bookmarkDefaultsKey)
        } else {
            defaults.removeObject(forKey: bookmarkDefaultsKey)
        }
    }

    static func loadBookmark(defaults: UserDefaults = .standard) throws -> SecurityScopedBookmark? {
        guard let data = defaults.data(forKey: bookmarkDefaultsKey) else { return nil }
        return try JSONDecoder().decode(SecurityScopedBookmark.self, from: data)
    }

    static func resolveBookmark(_ bookmark: SecurityScopedBookmark) throws -> URL {
        let resolved = try bookmark.resolve()
        guard !resolved.isStale else { throw AppSettingsError.staleBookmark }
        return resolved.url
    }

    static func exportSettings(_ snapshot: SettingsSnapshot, to url: URL) throws {
        try snapshot.save(to: url)
    }

    static func importSettings(from url: URL) throws -> SettingsSnapshot {
        try SettingsSnapshot.load(from: url)
    }

    static func diagnosticReport(
        appVersion: String,
        recentBatchCount: Int,
        tasks: [WorkflowTask],
        thirdPartyNotice: String = "ThirdParty/licenses"
    ) -> DiagnosticReport {
        let summaries = tasks.map {
            DiagnosticTaskSummary(
                role: roleName($0.role),
                status: $0.status,
                filename: $0.inputURL.lastPathComponent
            )
        }
        return DiagnosticReport(
            appVersion: appVersion,
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: currentArchitecture,
            recentBatchCount: recentBatchCount,
            tasks: summaries,
            capabilities: ["audio-mp3", "subtitle-lrc", "pairing", "security-scoped-bookmark"],
            thirdPartyNotice: thirdPartyNotice
        )
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func roleName(_ role: WorkflowTaskRole) -> String {
        switch role {
        case .pairing: return "pairing"
        case .audio: return "audio"
        case .subtitle: return "subtitle"
        }
    }
}

enum AppSettingsError: LocalizedError, Equatable {
    case staleBookmark
    case invalidBookmark
    case importWhileRunning
    case cannotAccessOutputDirectory

    var errorDescription: String? {
        switch self {
        case .staleBookmark: return "输出目录授权已过期，请重新选择目录"
        case .invalidBookmark: return "输出目录授权无效，请重新选择目录"
        case .importWhileRunning: return "任务运行期间不能导入设置"
        case .cannotAccessOutputDirectory: return "无法访问输出目录"
        }
    }
}
