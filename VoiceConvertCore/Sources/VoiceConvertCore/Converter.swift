import Foundation

public enum SubtitleConversionMode: String, Equatable, Sendable {
    case lenient
    case strict
}

public enum SubtitleConversionError: Error, Equatable, Sendable, LocalizedError {
    case missingWebVTTHeader
    case malformedCue(reason: String)

    public var errorDescription: String? {
        switch self {
        case .missingWebVTTHeader: return "严格模式要求 WEBVTT 文件头"
        case let .malformedCue(reason): return "无效 cue：\(reason)"
        }
    }
}

public struct SubtitleCuePreview: Equatable, Sendable {
    public let startMs: Int
    public let text: String
    public let speaker: String?

    public init(startMs: Int, text: String, speaker: String?) {
        self.startMs = startMs
        self.text = text
        self.speaker = speaker
    }
}

public struct SubtitlePreviewStatistics: Equatable, Sendable {
    public let noteBlockCount: Int
    public let styleBlockCount: Int
    public let regionBlockCount: Int
    public let emptyCueCount: Int
    public let validCueCount: Int

    public init(noteBlockCount: Int, styleBlockCount: Int, regionBlockCount: Int, emptyCueCount: Int, validCueCount: Int) {
        self.noteBlockCount = noteBlockCount
        self.styleBlockCount = styleBlockCount
        self.regionBlockCount = regionBlockCount
        self.emptyCueCount = emptyCueCount
        self.validCueCount = validCueCount
    }
}

public struct SubtitlePreview: Equatable, Sendable {
    public let cues: [SubtitleCuePreview]
    public let statistics: SubtitlePreviewStatistics
    public let warnings: [String]

    public init(cues: [SubtitleCuePreview], statistics: SubtitlePreviewStatistics, warnings: [String]) {
        self.cues = cues
        self.statistics = statistics
        self.warnings = warnings
    }

    public var noteBlockCount: Int { statistics.noteBlockCount }
    public var styleBlockCount: Int { statistics.styleBlockCount }
    public var regionBlockCount: Int { statistics.regionBlockCount }
    public var emptyCueCount: Int { statistics.emptyCueCount }
    public var validCueCount: Int { statistics.validCueCount }
}

/// vtt→lrc 纯函数转换核心；不含任何 UI / 文件系统依赖。
public struct VttToLrcConverter: Sendable {
    public init() {}

    /// 旧默认 API：保持宽松、无抛错和空输入返回空串的行为。
    public func convert(_ vtt: String, keepSpeakers: Bool = false) -> String {
        render(preview: previewLenient(vtt), keepSpeakers: keepSpeakers)
    }

    public func preview(_ vtt: String, mode: SubtitleConversionMode = .lenient) throws -> SubtitlePreview {
        switch mode {
        case .lenient: return previewLenient(vtt)
        case .strict: return try previewStrict(vtt)
        }
    }

    public func convert(_ vtt: String, keepSpeakers: Bool = false, mode: SubtitleConversionMode) throws -> String {
        render(preview: try preview(vtt, mode: mode), keepSpeakers: keepSpeakers)
    }

    private struct RawCue {
        let startMs: Int
        let bodyLines: [String]
    }

    private struct ParsedBlocks {
        var rawCues: [RawCue] = []
        var noteBlockCount = 0
        var styleBlockCount = 0
        var regionBlockCount = 0
        var malformedCueCount = 0
    }

    private enum StructuralBlock { case header, note, style, region }

    private struct CueParseFailure: Error {
        let reason: String
    }

    private func previewLenient(_ vtt: String) -> SubtitlePreview {
        makePreview(from: parseBlocksLenient(lines: normalizedLines(vtt)))
    }

    private func previewStrict(_ vtt: String) throws -> SubtitlePreview {
        let lines = normalizedLines(vtt)
        guard let first = lines.first, first.hasPrefix("WEBVTT") else {
            throw SubtitleConversionError.missingWebVTTHeader
        }
        return makePreview(from: try parseBlocksStrict(lines: lines))
    }

    private func parseBlocksLenient(lines: [String]) -> ParsedBlocks {
        var result = ParsedBlocks()
        for block in blocks(from: lines) {
            guard let head = block.first else { continue }
            if countStructuralBlock(head, in: &result) { continue }
            switch cueFrom(block: block) {
            case let .success(cue): result.rawCues.append(cue)
            case .failure: result.malformedCueCount += 1
            }
        }
        return result
    }

    private func parseBlocksStrict(lines: [String]) throws -> ParsedBlocks {
        var result = ParsedBlocks()
        for block in blocks(from: lines) {
            guard let head = block.first else { continue }
            if countStructuralBlock(head, in: &result) { continue }
            switch cueFrom(block: block) {
            case let .success(cue): result.rawCues.append(cue)
            case let .failure(failure): throw SubtitleConversionError.malformedCue(reason: failure.reason)
            }
        }
        return result
    }

    private func makePreview(from parsed: ParsedBlocks) -> SubtitlePreview {
        let cleaned = parsed.rawCues.compactMap(cleanup)
        let sorted = cleaned.enumerated()
            .sorted { ($0.element.startMs, $0.offset) < ($1.element.startMs, $1.offset) }
            .map(\.element)
        let emptyCueCount = parsed.rawCues.count - cleaned.count
        var warnings: [String] = []
        if parsed.malformedCueCount > 0 { warnings.append("已忽略 \(parsed.malformedCueCount) 个无效 cue") }
        if emptyCueCount > 0 { warnings.append("已忽略 \(emptyCueCount) 个空 cue") }
        return SubtitlePreview(
            cues: sorted.map { SubtitleCuePreview(startMs: $0.startMs, text: $0.text, speaker: $0.speaker) },
            statistics: SubtitlePreviewStatistics(
                noteBlockCount: parsed.noteBlockCount,
                styleBlockCount: parsed.styleBlockCount,
                regionBlockCount: parsed.regionBlockCount,
                emptyCueCount: emptyCueCount,
                validCueCount: sorted.count
            ),
            warnings: warnings
        )
    }

    private func blocks(from lines: [String]) -> [[String]] {
        var result: [[String]] = []
        var block: [String] = []
        for line in lines {
            if line.isEmpty {
                if !block.isEmpty { result.append(block); block.removeAll(keepingCapacity: true) }
            } else {
                block.append(line)
            }
        }
        if !block.isEmpty { result.append(block) }
        return result
    }

    private func normalizedLines(_ vtt: String) -> [String] {
        var text = Substring(vtt)
        if text.hasPrefix("\u{FEFF}") { text = text.dropFirst() }
        return text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func countStructuralBlock(_ line: String, in result: inout ParsedBlocks) -> Bool {
        switch structuralBlock(for: line) {
        case .header?: return true
        case .note?: result.noteBlockCount += 1; return true
        case .style?: result.styleBlockCount += 1; return true
        case .region?: result.regionBlockCount += 1; return true
        case nil: return false
        }
    }

    private func structuralBlock(for line: String) -> StructuralBlock? {
        if line.hasPrefix("WEBVTT") { return .header }
        if line == "NOTE" || line.hasPrefix("NOTE ") || line.hasPrefix("NOTE\t") { return .note }
        if line == "STYLE" { return .style }
        if line == "REGION" { return .region }
        return nil
    }

    private func cueFrom(block: [String]) -> Result<RawCue, CueParseFailure> {
        guard let timingIndex = block.firstIndex(where: { $0.contains("-->") }) else {
            return .failure(CueParseFailure(reason: "缺少时间轴"))
        }
        let timing = block[timingIndex]
        guard let arrow = timing.range(of: "-->") else { return .failure(CueParseFailure(reason: "缺少时间轴")) }
        let start = timing[timing.startIndex..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let endToken = timing[arrow.upperBound...].split(
            maxSplits: 1,
            omittingEmptySubsequences: true,
            whereSeparator: { $0 == " " || $0 == "\t" }
        ).first.map(String.init)
        guard let endToken, !endToken.isEmpty else { return .failure(CueParseFailure(reason: "缺少结束时间")) }
        guard let startMs = Self.parseTimestamp(start), Self.parseTimestamp(endToken) != nil else {
            return .failure(CueParseFailure(reason: "时间轴格式错误"))
        }
        return .success(RawCue(startMs: startMs, bodyLines: Array(block[block.index(after: timingIndex)...])))
    }

    static func parseTimestamp(_ value: String) -> Int? {
        let parts = value.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        var seconds = 0
        for part in parts.dropLast() {
            guard !part.isEmpty, part.allSatisfy(\.isASCII), let number = Int(part), number >= 0 else { return nil }
            seconds = (seconds + number) * 60
        }
        let last = parts.last!.split(separator: ".", omittingEmptySubsequences: false)
        guard (last.count == 1 || last.count == 2), !last[0].isEmpty, let finalSeconds = Int(last[0]), finalSeconds >= 0 else { return nil }
        seconds += finalSeconds
        var milliseconds = seconds * 1_000
        if last.count == 2 {
            let fraction = last[1]
            guard !fraction.isEmpty, fraction.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            let digits = fraction.prefix(3)
            var value = Int(digits) ?? 0
            if digits.count < 3 { value *= Int(pow(10.0, Double(3 - digits.count))) }
            milliseconds += value
        }
        return milliseconds
    }

    private func cleanup(_ cue: RawCue) -> ConvertedCue? {
        var speaker: String?
        var pieces: [String] = []
        for line in cue.bodyLines {
            let (stripped, voice) = stripTags(line)
            if speaker == nil { speaker = voice }
            let text = Self.decodeEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { pieces.append(text) }
        }
        let text = pieces.joined(separator: " ")
        guard !text.isEmpty else { return nil }
        return ConvertedCue(startMs: cue.startMs, text: text, speaker: speaker)
    }

    private func stripTags(_ text: String) -> (String, String?) {
        var output = ""
        var voice: String?
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "<", let close = text[index...].firstIndex(of: ">") {
                if voice == nil { voice = Self.voiceName(in: text[text.index(after: index)..<close]) }
                index = text.index(after: close)
            } else {
                output.append(text[index])
                index = text.index(after: index)
            }
        }
        return (output, voice)
    }

    static func voiceName(in inner: Substring) -> String? {
        guard let first = inner.first, first.lowercased() == "v" else { return nil }
        let remaining = inner.dropFirst()
        guard let separator = remaining.first, separator == " " || separator == "\t" else { return nil }
        let name = remaining.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        return name.map(String.init)
    }

    static func decodeEntities(_ text: String) -> String {
        let named: [String: Character] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "&", let semi = text[index...].firstIndex(of: ";"), text.distance(from: index, to: semi) <= 32 else {
                output.append(text[index]); index = text.index(after: index); continue
            }
            let token = String(text[text.index(after: index)..<semi])
            let scalar: Unicode.Scalar?
            if token.hasPrefix("#x") || token.hasPrefix("#X") {
                scalar = UInt32(token.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init)
            } else if token.hasPrefix("#") {
                scalar = UInt32(token.dropFirst()).flatMap(Unicode.Scalar.init)
            } else {
                scalar = nil
            }
            if let scalar { output.append(Character(scalar)); index = text.index(after: semi) }
            else if let character = named[token] { output.append(character); index = text.index(after: semi) }
            else { output.append("&"); index = text.index(after: index) }
        }
        return output
    }

    private func render(preview: SubtitlePreview, keepSpeakers: Bool) -> String {
        preview.cues.map { cue in
            let prefix = keepSpeakers && cue.speaker?.isEmpty == false ? cue.speaker! + "：" : ""
            return Self.formatLrcTimestamp(ms: cue.startMs) + prefix + cue.text
        }.joined(separator: "\n")
    }

    static func formatLrcTimestamp(ms: Int) -> String {
        let centiseconds = (ms + 5) / 10
        return String(format: "[%02d:%02d.%02d]", centiseconds / 6_000, (centiseconds % 6_000) / 100, centiseconds % 100)
    }
}

public struct ConvertedCue: Equatable, Sendable {
    public let startMs: Int
    public let text: String
    public let speaker: String?

    public init(startMs: Int, text: String, speaker: String?) {
        self.startMs = startMs
        self.text = text
        self.speaker = speaker
    }
}

public enum CoreInfo {
    public static let version = "0.1.0"
}
