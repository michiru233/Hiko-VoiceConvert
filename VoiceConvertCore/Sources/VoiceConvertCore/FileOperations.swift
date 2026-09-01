import Foundation

/// 单个文件转换结果——GUI 列表状态的唯一来源。
public enum FileConversionOutcome: Equatable, Sendable {
    case created                         // 成功
    case alreadyExists                   // 已存在（目标 .lrc 在，不覆盖）
    case createdWithWarnings([String])   // 成功，但宽松解析跳过了部分内容
    case skipped(reason: String)         // 调用方主动跳过
    case failed(reason: String)          // 失败
}

public enum SubtitleFileEncoding: String, Equatable, Sendable {
    case utf8
    case utf8BOM
    case utf16LittleEndian
    case utf16BigEndian
}

public enum SubtitleFileDecodingError: Error, Equatable, Sendable, LocalizedError {
    case unsupportedEncoding
    case invalidText(SubtitleFileEncoding)

    public var errorDescription: String? {
        switch self {
        case .unsupportedEncoding:
            return "不支持的字幕编码；仅支持 UTF-8、UTF-8 BOM、UTF-16 LE BOM 和 UTF-16 BE BOM"
        case let .invalidText(encoding):
            return "字幕内容不是有效的 \(encoding.rawValue) 文本"
        }
    }
}

extension VttToLrcConverter {
    private static let audioExtensions: Set<String> = [
        "mp3", "wav", "flac", "m4a", "aac", "ogg", "opus", "wma", "aiff", "aif", "ape",
    ]

    /// 源 .vtt 同目录、同基名的 .lrc 路径。基名自带音频后缀时，输出名再剥一层。
    public static func lrcDestination(for vttURL: URL) -> URL {
        var destination = vttURL.deletingPathExtension()
        let stem = destination.lastPathComponent
        let lowered = stem.lowercased()
        if let ext = audioExtensions.first(where: { lowered.hasSuffix(".\($0)") }), stem.count > ext.count + 1 {
            destination.deletePathExtension()
        }
        return destination.appendingPathExtension("lrc")
    }

    /// 检测并解码允许的字幕编码。无 BOM 数据只接受严格有效的 UTF-8。
    public static func decodeSubtitleData(_ data: Data) throws -> (text: String, encoding: SubtitleFileEncoding) {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            guard let text = String(data: data.dropFirst(3), encoding: .utf8) else {
                throw SubtitleFileDecodingError.invalidText(.utf8BOM)
            }
            return (text, .utf8BOM)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) else {
                throw SubtitleFileDecodingError.invalidText(.utf16LittleEndian)
            }
            return (text, .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            guard let text = String(data: data.dropFirst(2), encoding: .utf16BigEndian) else {
                throw SubtitleFileDecodingError.invalidText(.utf16BigEndian)
            }
            return (text, .utf16BigEndian)
        }
        guard !data.contains(0), let text = String(data: data, encoding: .utf8) else {
            throw SubtitleFileDecodingError.unsupportedEncoding
        }
        return (text, .utf8)
    }

    /// 读取文件、转换并落盘。默认宽松模式，输出 UTF-8 无 BOM，且绝不覆盖已有目标。
    /// 没有有效文本时返回失败，不创建空 .lrc 文件。
    @discardableResult
    public func convertFile(
        at vttURL: URL,
        keepSpeakers: Bool = false,
        mode: SubtitleConversionMode = .lenient
    ) -> FileConversionOutcome {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vttURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .failed(reason: "源文件不存在")
        }
        let destination = Self.lrcDestination(for: vttURL)
        guard !fileManager.fileExists(atPath: destination.path) else { return .alreadyExists }

        do {
            let decoded = try Self.decodeSubtitleData(Data(contentsOf: vttURL))
            let preview = try preview(decoded.text, mode: mode)
            guard preview.validCueCount > 0 else {
                return .failed(reason: "字幕中没有有效文本")
            }
            let lrcText = try convert(decoded.text, keepSpeakers: keepSpeakers, mode: mode)
            try Data((lrcText + "\n").utf8).write(to: destination, options: [.atomic])
            return preview.warnings.isEmpty ? .created : .createdWithWarnings(preview.warnings)
        } catch let error as LocalizedError {
            return .failed(reason: error.errorDescription ?? error.localizedDescription)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }

    /// Reads, converts, and writes to an explicit destination. The destination's
    /// parent directory is created as needed and the file is written atomically.
    /// Existing files are preserved unless `overwrite` is explicitly enabled.
    @discardableResult
    public func convertFile(
        at vttURL: URL,
        destination: URL,
        keepSpeakers: Bool = false,
        mode: SubtitleConversionMode = .lenient,
        overwrite: Bool = false,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) -> FileConversionOutcome {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: vttURL.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return .failed(reason: "源文件不存在")
        }
        if isCancelled?() == true { return .skipped(reason: "转换已取消") }
        if fileManager.fileExists(atPath: destination.path), !overwrite { return .alreadyExists }

        do {
            let decoded = try Self.decodeSubtitleData(Data(contentsOf: vttURL))
            let preview = try preview(decoded.text, mode: mode)
            guard preview.validCueCount > 0 else {
                return .failed(reason: "字幕中没有有效文本")
            }
            let lrcText = try convert(decoded.text, keepSpeakers: keepSpeakers, mode: mode)
            if isCancelled?() == true { return .skipped(reason: "转换已取消") }
            try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((lrcText + "\n").utf8).write(to: destination, options: [.atomic])
            return preview.warnings.isEmpty ? .created : .createdWithWarnings(preview.warnings)
        } catch let error as LocalizedError {
            return .failed(reason: error.errorDescription ?? error.localizedDescription)
        } catch {
            return .failed(reason: error.localizedDescription)
        }
    }
    /// 收集待转换清单：路径是文件则原样返回（仅 .vtt），目录则递归全部子目录。
    public static func collectVTTFiles(at path: URL) -> [URL] {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path.path, isDirectory: &isDirectory) else { return [] }
        if !isDirectory.boolValue {
            return path.pathExtension.lowercased() == "vtt" ? [path] : []
        }
        var found: [URL] = []
        if let enumerator = fileManager.enumerator(at: path, includingPropertiesForKeys: [.isRegularFileKey], options: []) {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "vtt" {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]), values.isRegularFile == true else { continue }
                found.append(url)
            }
        }
        return found.sorted { $0.path < $1.path }
    }
}
