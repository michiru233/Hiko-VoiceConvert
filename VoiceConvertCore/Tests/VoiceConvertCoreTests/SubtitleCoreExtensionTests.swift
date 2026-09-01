import Foundation
import Testing
@testable import VoiceConvertCore

struct SubtitleCoreExtensionTests {
    private let converter = VttToLrcConverter()

    private func makeTempDir() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("subtitle-core-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test func previewReportsStructuralBlocksEmptyAndValidCues() throws {
        let vtt = """
        WEBVTT

        NOTE comment

        STYLE
        ::cue { color: red }

        REGION
        id:bottom

        00:01.000 --> 00:02.000
        <i></i>

        00:03.000 --> 00:04.000
        usable
        """

        let preview = try converter.preview(vtt)
        #expect(preview.noteBlockCount == 1)
        #expect(preview.styleBlockCount == 1)
        #expect(preview.regionBlockCount == 1)
        #expect(preview.emptyCueCount == 1)
        #expect(preview.validCueCount == 1)
        #expect(preview.cues == [SubtitleCuePreview(startMs: 3_000, text: "usable", speaker: nil)])
        #expect(preview.warnings == ["已忽略 1 个空 cue"])
    }

    @Test func strictModeRejectsMissingHeaderAndMalformedCueWhileDefaultRemainsLenient() {
        let missingHeader = "00:01.000 --> 00:02.000\ntext"
        #expect(converter.convert(missingHeader) == "[00:01.00]text")
        #expect(throws: SubtitleConversionError.missingWebVTTHeader) {
            try converter.convert(missingHeader, mode: .strict)
        }

        let malformed = "WEBVTT\n\nnot a cue"
        #expect(converter.convert(malformed) == "")
        #expect(throws: SubtitleConversionError.malformedCue(reason: "缺少时间轴")) {
            try converter.preview(malformed, mode: .strict)
        }
    }

    @Test(arguments: [
        (Data("WEBVTT".utf8), SubtitleFileEncoding.utf8),
        (Data([0xEF, 0xBB, 0xBF] + Array("WEBVTT".utf8)), SubtitleFileEncoding.utf8BOM),
        (Data([0xFF, 0xFE, 0x57, 0x00, 0x45, 0x00]), SubtitleFileEncoding.utf16LittleEndian),
        (Data([0xFE, 0xFF, 0x00, 0x57, 0x00, 0x45]), SubtitleFileEncoding.utf16BigEndian),
    ]) func supportedEncodingsDecodeWithDetectedEncoding(_ data: Data, _ expected: SubtitleFileEncoding) throws {
        let decoded = try VttToLrcConverter.decodeSubtitleData(data)
        #expect(decoded.encoding == expected)
        #expect(decoded.text.hasPrefix("WE"))
    }

    @Test func unsupportedAndInvalidEncodingFailExplicitly() {
        #expect(throws: SubtitleFileDecodingError.unsupportedEncoding) {
            try VttToLrcConverter.decodeSubtitleData(Data([0xFF, 0x00, 0x61, 0x00]))
        }
        #expect(throws: SubtitleFileDecodingError.unsupportedEncoding) {
            try VttToLrcConverter.decodeSubtitleData(Data([0x57, 0x00, 0x45, 0x00]))
        }
    }

    @Test func fileWithoutValidTextFailsWithoutCreatingOutput() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("empty.vtt")
        try Data("WEBVTT\n\n00:01.000 --> 00:02.000\n<i></i>\n".utf8).write(to: source)

        let outcome = converter.convertFile(at: source)
        #expect(outcome == .failed(reason: "字幕中没有有效文本"))
        #expect(!FileManager.default.fileExists(atPath: VttToLrcConverter.lrcDestination(for: source).path))
    }

    @Test func fileConversionReturnsWarningsForLenientlySkippedContent() throws {
        let directory = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("mixed.vtt")
        try Data("WEBVTT\n\nbroken\n\n00:01.000 --> 00:02.000\nvalid\n".utf8).write(to: source)

        let outcome = converter.convertFile(at: source)
        #expect(outcome == .createdWithWarnings(["已忽略 1 个无效 cue"]))
    }
}
