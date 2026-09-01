import Foundation
import Testing
@testable import VoiceConvertCore

/// 文件级行为规格：GUI「成功 / 已存在 / 失败」状态与递归收集的唯一事实来源。
struct FileOperationTests {

    private let converter = VttToLrcConverter()

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vttlrc-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func write(_ text: String, to url: URL) throws {
        try Data(text.utf8).write(to: url, options: [.atomic])
    }

    @Test func lrcDestinationSitsBesideSourceWithSameBaseName() {
        let source = URL(fileURLWithPath: "/somewhere/album/track01.vtt")
        let dest = VttToLrcConverter.lrcDestination(for: source)
        #expect(dest == URL(fileURLWithPath: "/somewhere/album/track01.lrc"))
        #expect(dest.deletingLastPathComponent() == source.deletingLastPathComponent())
    }

    @Test func convertFileCreatesSiblingLrcWithUtf8NoBomAndTrailingNewline() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vtt = dir.appendingPathComponent("track.vtt")
        try write("WEBVTT\n\n00:05.000 --> 00:06.000\n内容\n", to: vtt)

        let outcome = converter.convertFile(at: vtt, keepSpeakers: false)
        #expect(outcome == .created)

        let dest = VttToLrcConverter.lrcDestination(for: vtt)
        let data = try Data(contentsOf: dest)
        #expect(!data.starts(with: [0xEF, 0xBB, 0xBF]))
        #expect(String(decoding: data, as: UTF8.self) == "[00:05.00]内容\n")
    }

    /// 拍板第二条：目标已存在→不覆盖、报告已存在。
    @Test func existingLrcIsNeverOverwrittenAndReportedAsAlreadyExists() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vtt = dir.appendingPathComponent("track.vtt")
        try write("WEBVTT\n\n00:05.000 --> 00:06.000\n新内容\n", to: vtt)
        let dest = VttToLrcConverter.lrcDestination(for: vtt)
        try write("哨兵内容\n", to: dest)

        let outcome = converter.convertFile(at: vtt, keepSpeakers: false)
        #expect(outcome == .alreadyExists)
        #expect(try String(decoding: Data(contentsOf: dest), as: UTF8.self) == "哨兵内容\n")
    }

    @Test func missingSourceReportedAsFailed() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outcome = converter.convertFile(
            at: dir.appendingPathComponent("ghost.vtt"),
            keepSpeakers: false
        )
        guard case .failed(let reason) = outcome else {
            Issue.record("期望 failed，实际 \(outcome)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func recursiveCollectionFindsNestedVttFilesOnlySortedByPath() throws {
        let root = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("x", to: root.appendingPathComponent("one.vtt"))
        try write("y", to: root.appendingPathComponent("noise.txt"))
        try write("z", to: root.appendingPathComponent("stray.lrc"))
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try write("a", to: sub.appendingPathComponent("two.vtt"))
        let deep = sub.appendingPathComponent("deep", isDirectory: true)
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try write("b", to: deep.appendingPathComponent("three.VTT"))

        let found = VttToLrcConverter.collectVTTFiles(at: root)
        // 收集顺序 = 完整路径字典序（确定性行为）：子目录前缀按字符比较。
        #expect(found.map(\.lastPathComponent) == ["one.vtt", "three.VTT", "two.vtt"])
    }

    @Test func collectionOnSingleFileReturnsItOnlyWhenVttExtension() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vtt = dir.appendingPathComponent("only.vtt")
        let txt = dir.appendingPathComponent("note.txt")
        try write("x", to: vtt)
        try write("y", to: txt)
        #expect(VttToLrcConverter.collectVTTFiles(at: vtt).map(\.path) == [vtt.path])
        #expect(VttToLrcConverter.collectVTTFiles(at: txt).isEmpty)
    }

    @Test func nonExistentPathCollectsNothing() {
        #expect(VttToLrcConverter.collectVTTFiles(at: URL(fileURLWithPath: "/nonexistent-vttlrc")).isEmpty)
    }

    // MARK: - 音频后缀剥离：「xxx.mp3.vtt」→「xxx.lrc」

    @Test func mp3SuffixInSourceNameIsStripped() {
        let dest = VttToLrcConverter.lrcDestination(for: URL(fileURLWithPath: "/somewhere/a.mp3.vtt"))
        #expect(dest.lastPathComponent == "a.lrc")
    }

    @Test func wavSuffixInSourceNameIsStripped() {
        let dest = VttToLrcConverter.lrcDestination(for: URL(fileURLWithPath: "/somewhere/b.wav.vtt"))
        #expect(dest.lastPathComponent == "b.lrc")
    }

    /// 清单内后缀大小写不敏感：源叫「C.MP3.VTT」也剥。
    @Test func audioSuffixMatchingIsCaseInsensitive() {
        #expect(VttToLrcConverter.lrcDestination(
            for: URL(fileURLWithPath: "/somewhere/C.MP3.VTT")).lastPathComponent == "C.lrc")
        #expect(VttToLrcConverter.lrcDestination(
            for: URL(fileURLWithPath: "/somewhere/d.Flac.vtt")).lastPathComponent == "d.lrc")
    }

    @Test func sourceWithoutAudioSuffixIsUnaffected() {
        #expect(VttToLrcConverter.lrcDestination(
            for: URL(fileURLWithPath: "/somewhere/track01.vtt")).lastPathComponent == "track01.lrc")
    }

    @Test func chineseAlbumTrackNamesStripAudioSuffixCorrectly() {
        let dest = VttToLrcConverter.lrcDestination(
            for: URL(fileURLWithPath: "/书/第1章『厨房』双人篇【音轨】.mp3.vtt"))
        #expect(dest.lastPathComponent == "第1章『厨房』双人篇【音轨】.lrc")
    }

    /// 拍板：只剥一层防误伤。
    @Test func onlyOneAudioLayerIsStripped() {
        #expect(VttToLrcConverter.lrcDestination(
            for: URL(fileURLWithPath: "/m/a.mp3.wav.vtt")).lastPathComponent == "a.mp3.lrc")
    }

    /// 全清单逐项：每个音频扩展名都剥、且不影响非清单后缀。
    @Test func everyListedAudioExtensionIsStrippedButOthersAreNot() {
        let listed = ["mp3", "wav", "flac", "m4a", "aac", "ogg", "opus", "wma", "aiff", "aif", "ape"]
        for ext in listed {
            let dest = VttToLrcConverter.lrcDestination(
                for: URL(fileURLWithPath: "/m/song.\(ext).vtt"))
            #expect(dest.lastPathComponent == "song.lrc", "扩展名 \(ext) 未被剥离")
        }
        #expect(VttToLrcConverter.lrcDestination(
            for: URL(fileURLWithPath: "/m/song.txt.vtt")).lastPathComponent == "song.txt.lrc")
    }

    /// 端到端：真实落盘时 convertFile 也按剥好的名字写（不 mock）。
    @Test func convertedFileOnDiskDropsAudioSuffixFromName() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vtt = dir.appendingPathComponent("第3章.mp3.vtt")
        try write("WEBVTT\n\n00:05.000 --> 00:06.000\n内容\n", to: vtt)

        let outcome = converter.convertFile(at: vtt, keepSpeakers: false)
        #expect(outcome == .created)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("第3章.lrc").path))
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("第3章.mp3.lrc").path))
    }
}
