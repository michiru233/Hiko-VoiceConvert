import Foundation
import AVFoundation

public struct AudioFormatSummary: Equatable, Sendable {
    public let sampleRate: Double
    public let channels: Int
    public let duration: TimeInterval

    public init(sampleRate: Double, channels: Int, duration: TimeInterval) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.duration = duration
    }
}

public enum OutputPathError: LocalizedError, Equatable {
    case outsideRoot
    case invalidRelativePath

    public var errorDescription: String? {
        switch self {
        case .outsideRoot: return "输出路径不能离开输出目录"
        case .invalidRelativePath: return "输入相对路径无效"
        }
    }
}

public enum OutputPathResolver {
    public static func resolve(input: URL, root: URL, relativeRoot: URL?) throws -> URL {
        let displayRoot = root.standardizedFileURL
        let canonicalRoot = displayRoot.resolvingSymlinksInPath().standardizedFileURL
        let inputURL = input.resolvingSymlinksInPath().standardizedFileURL
        let baseURL = (relativeRoot ?? inputURL.deletingLastPathComponent())
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let basePath = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
        guard inputURL.path.hasPrefix(basePath) else { throw OutputPathError.invalidRelativePath }
        let relative = String(inputURL.path.dropFirst(basePath.count))
        guard !relative.isEmpty, !relative.hasPrefix("/") else { throw OutputPathError.invalidRelativePath }
        let outputRelative = displayRoot
            .appendingPathComponent(relative)
            .deletingPathExtension()
            .appendingPathExtension("mp3")
        let candidate = outputRelative.standardizedFileURL
        let canonicalCandidate = candidate.resolvingSymlinksInPath().standardizedFileURL
        let prefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        guard canonicalCandidate.path == canonicalRoot.path || canonicalCandidate.path.hasPrefix(prefix) else {
            throw OutputPathError.outsideRoot
        }
        return candidate
    }

    public static func uniqueURL(_ proposed: URL, reserved: inout Set<String>) -> URL {
        let directory = proposed.deletingLastPathComponent()
        let ext = proposed.pathExtension
        let stem = proposed.deletingPathExtension().lastPathComponent
        var candidate = proposed
        var index = 0
        func key(_ url: URL) -> String {
            url.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        }
        while reserved.contains(key(candidate)) || FileManager.default.fileExists(atPath: candidate.path) {
            index += 1
            candidate = directory.appendingPathComponent("\(stem)-\(index).\(ext)")
        }
        reserved.insert(key(candidate))
        return candidate
    }
}

public struct AudioInputScanner {
    public init() {}

    public func scan(_ urls: [URL]) -> [URL] {
        var result: [URL] = []
        var seen = Set<String>()
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                guard let enumerator = FileManager.default.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for case let child as URL in enumerator {
                    let values = try? child.resourceValues(forKeys: [.isRegularFileKey])
                    guard values?.isRegularFile == true else { continue }
                    let canonicalChild = child.resolvingSymlinksInPath().standardizedFileURL
                    if isSupportedAudio(canonicalChild),
                       seen.insert(canonicalChild.path).inserted {
                        result.append(canonicalChild)
                    }
                }
            } else {
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
                if isSupportedAudio(canonicalURL), seen.insert(canonicalURL.path).inserted {
                    result.append(canonicalURL)
                }
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func isSupportedAudio(_ url: URL) -> Bool {
        ConversionEngine.supportedExtensions.contains(url.pathExtension.lowercased())
    }
}
