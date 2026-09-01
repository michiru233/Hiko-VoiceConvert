import Foundation
import Testing
@testable import VoiceConvertCore

struct PairBatchExecutorTests {
    private actor Counter {
        private var value = 0
        func increment() -> Int { value += 1; return value }
        func current() -> Int { value }
    }

    private func fixture() throws -> (root: URL, result: PairingResult, audio: URL, subtitle: URL, output: URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pair-batch-\(UUID().uuidString)")
        let input = root.appendingPathComponent("input")
        let output = root.appendingPathComponent("output")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        let audio = input.appendingPathComponent("nested/scene.wav")
        let subtitle = input.appendingPathComponent("nested/scene.wav.vtt")
        try FileManager.default.createDirectory(at: audio.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audio)
        try Data("WEBVTT\n\n00:01.000 --> 00:02.000\nFirst line\n".utf8).write(to: subtitle)
        let audioInput = ScannedInput(url: audio, kind: .audio, root: input, relativePath: "nested/scene.wav")
        let subtitleInput = ScannedInput(url: subtitle, kind: .subtitle, root: input, relativePath: "nested/scene.wav.vtt")
        return (root, PairingResult(pairs: [AudioSubtitlePair(audio: audioInput, subtitle: subtitleInput)], issues: []), audio, subtitle, output)
    }

    @Test func planBuildsParentAndIndependentChildrenWithSharedStem() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output, outputSubdirectory: "paired")
        #expect(plan.tasks.count == 3)
        let parent = try #require(plan.tasks.first { $0.role == .pairing })
        let children = plan.tasks.filter { $0.parentID == parent.id }
        #expect(children.count == 2)
        #expect(children.map(\.operation).contains(.mp3))
        #expect(children.map(\.operation).contains(.lrc))
        let outputs = children.compactMap(\.outputURL)
        #expect(outputs.map { $0.deletingPathExtension().path }.allSatisfy { $0 == outputs.first?.deletingPathExtension().path })
        #expect(outputs.allSatisfy { $0.path.contains("/paired/nested/") })
    }

    @Test func suffixPreservesExistingPairAndBothOutputsUseSameSuffix() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let existing = value.output.appendingPathComponent("nested/scene.mp3")
        try FileManager.default.createDirectory(at: existing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("sentinel".utf8).write(to: existing)
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output, policy: .suffix)
        let outputs = plan.tasks.compactMap(\.outputURL)
        #expect(outputs.contains { $0.lastPathComponent == "scene (1).mp3" })
        #expect(outputs.contains { $0.lastPathComponent == "scene (1).lrc" })
        #expect(try Data(contentsOf: existing) == Data("sentinel".utf8))
    }

    @Test func successfulAudioAndFailedSubtitleRetryOnlySubtitle() async throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output)
        let counter = Counter()
        let audio: PairAudioExecutor = { _, output, _, _, _ in
            _ = await counter.increment()
            try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("mp3".utf8).write(to: output)
            return .succeeded
        }
        try Data("WEBVTT\n\nnot a cue\n".utf8).write(to: value.subtitle)
        let failed = await PairBatchExecutor().execute(plan: plan, audioExecutor: audio, mode: .strict)
        #expect(await counter.current() == 1)
        let subtitleTask = try #require(failed.tasks.first { $0.operation == .lrc })
        #expect({ if case .failed = subtitleTask.status { true } else { false } }())
        try Data("WEBVTT\n\n00:01.000 --> 00:02.000\nRecovered\n".utf8).write(to: value.subtitle)
        let retry = await PairBatchExecutor().retry(plan: failed, audioExecutor: audio)
        #expect(await counter.current() == 1)
        #expect(retry.tasks.first { $0.operation == .mp3 }?.status == .succeeded)
        #expect({ if case .failed = retry.tasks.first { $0.operation == .lrc }?.status { true } else { false } }())
        #expect({ if case .failed = retry.tasks.first { $0.role == .pairing }?.status { true } else { false } }())
    }

    @Test func audioFailureSkipsSubtitleAndRetryRestoresDependency() async throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output)
        let counter = Counter()
        let audio: PairAudioExecutor = { _, output, _, _, _ in
            let count = await counter.increment()
            if count == 1 { return .failed("damaged wav") }
            try? FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("mp3".utf8).write(to: output)
            return .succeeded
        }
        let failed = await PairBatchExecutor().execute(plan: plan, audioExecutor: audio)
        #expect(failed.tasks.first { $0.operation == .lrc }?.status == .skipped("音频转换失败，未生成字幕"))
        let retried = await PairBatchExecutor().retry(plan: failed, audioExecutor: audio)
        #expect(await counter.current() == 2)
        #expect(retried.tasks.first { $0.operation == .lrc }?.status == .succeeded)
        #expect(retried.tasks.first { $0.role == .pairing }?.status == .succeeded)
    }

    @Test func cancellationCancelsPendingTasksAndLeavesNoLrc() async throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output)
        let cancelled = await PairBatchExecutor().execute(plan: plan, audioExecutor: { _, _, _, _, _ in .cancelled }, isCancelled: { true })
        #expect(cancelled.tasks.first { $0.operation == .mp3 }?.status == .cancelled)
        #expect(cancelled.tasks.first { $0.operation == .lrc }?.status == .cancelled)
        #expect(!FileManager.default.fileExists(atPath: value.output.appendingPathComponent("nested/scene.lrc").path))
    }

    @Test func skipPreservesExistingPairOutputs() async throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output, policy: .skip)
        let mp3 = try #require(plan.plans.first?.mp3URL)
        let lrc = try #require(plan.plans.first?.lrcURL)
        try FileManager.default.createDirectory(at: mp3.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mp3 sentinel".utf8).write(to: mp3)
        try Data("lrc sentinel".utf8).write(to: lrc)

        let completed = await PairBatchExecutor().execute(plan: plan, audioExecutor: { _, _, _, _, _ in
            Issue.record("skip 策略不应执行音频子任务")
            return .succeeded
        })
        #expect(completed.tasks.first { $0.operation == .mp3 }?.status == .skipped("输出已存在，未覆盖"))
        #expect(completed.tasks.first { $0.operation == .lrc }?.status == .skipped("输出已存在，未覆盖"))
        #expect(try Data(contentsOf: mp3) == Data("mp3 sentinel".utf8))
        #expect(try Data(contentsOf: lrc) == Data("lrc sentinel".utf8))
    }

    @Test func overwriteConfirmsOnceForTheWholePairBatch() async throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let plan = try PairBatchPlanner().makePlan(from: value.result, outputRoot: value.output, policy: .overwrite)
        let mp3 = try #require(plan.plans.first?.mp3URL)
        let lrc = try #require(plan.plans.first?.lrcURL)
        try FileManager.default.createDirectory(at: mp3.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old mp3".utf8).write(to: mp3)
        try Data("old lrc".utf8).write(to: lrc)
        let confirmations = Counter()
        let completed = await PairBatchExecutor().execute(
            plan: plan,
            audioExecutor: { _, output, _, _, _ in
                try? Data("new mp3".utf8).write(to: output)
                return .succeeded
            },
            confirmOverwrite: { _ = await confirmations.increment(); return true }
        )
        #expect(await confirmations.current() == 1)
        #expect(completed.tasks.first { $0.operation == .mp3 }?.status == .succeeded)
        #expect(completed.tasks.first { $0.operation == .lrc }?.status == .succeeded)
        #expect(try Data(contentsOf: mp3) == Data("new mp3".utf8))
        #expect(String(decoding: try Data(contentsOf: lrc), as: UTF8.self).contains("[00:01.00]First line"))
    }

    @Test func explicitDestinationWritesAtomicallyAndKeepsExistingFileWithoutOverwrite() throws {
        let value = try fixture()
        defer { try? FileManager.default.removeItem(at: value.root) }
        let destination = value.output.appendingPathComponent("custom/scene.lrc")
        let converter = VttToLrcConverter()
        #expect(converter.convertFile(at: value.subtitle, destination: destination) == .created)
        let original = try Data(contentsOf: destination)
        #expect(original.first != 0xEF)
        #expect(String(decoding: original, as: UTF8.self).hasSuffix("\n"))
        #expect(converter.convertFile(at: value.subtitle, destination: destination) == .alreadyExists)
        #expect(try Data(contentsOf: destination) == original)
    }
}
