import Foundation
import AVFoundation
import Darwin
import VoiceConvertLAME

public struct CLIAudioConfiguration: Sendable {
    public var vbrQuality: Int
    public var fullStereo: Bool

    public init(vbrQuality: Int = 2, fullStereo: Bool = true) {
        self.vbrQuality = min(9, max(0, vbrQuality))
        self.fullStereo = fullStereo
    }
}

public struct CLIAudioDescription: Equatable, Sendable {
    public let sampleRate: Double
    public let channelCount: Int
    public let duration: TimeInterval
    public let frameLength: AVAudioFramePosition

    public init(sampleRate: Double, channelCount: Int, duration: TimeInterval, frameLength: AVAudioFramePosition) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.duration = duration
        self.frameLength = frameLength
    }
}

public enum CLIAudioError: LocalizedError, Equatable, Sendable {
    case unsupportedFormat(String)
    case cannotOpenInput(String)
    case cannotCreateOutput(String)
    case invalidAudio(String)
    case validationFailed(String)
    case cancelled
    case encoder(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let value): return "不支持的音频格式：\(value)"
        case .cannotOpenInput(let value): return "无法读取输入音频：\(value)"
        case .cannotCreateOutput(let value): return "无法创建输出文件：\(value)"
        case .invalidAudio(let value): return "音频数据无效：\(value)"
        case .validationFailed(let value): return "输出校验失败：\(value)"
        case .cancelled: return "转换已取消"
        case .encoder(let value): return "编码失败：\(value)"
        }
    }
}

public final class CLIAudioConverter: @unchecked Sendable {
    public static let supportedExtensions: Set<String> = ["wav", "flac", "aiff", "aif", "m4a"]

    public init() {}

    public func inspect(_ inputURL: URL) throws -> CLIAudioDescription {
        guard Self.supportedExtensions.contains(inputURL.pathExtension.lowercased()) else {
            throw CLIAudioError.unsupportedFormat(inputURL.pathExtension)
        }
        do {
            let file = try AVAudioFile(forReading: inputURL)
            let format = file.processingFormat
            guard format.sampleRate >= 8_000, format.sampleRate <= 48_000,
                  format.channelCount > 0, format.channelCount <= 2, file.length > 0 else {
                throw CLIAudioError.invalidAudio("仅支持 8kHz–48kHz、单声道或双声道且时长大于零的输入")
            }
            return CLIAudioDescription(sampleRate: format.sampleRate, channelCount: Int(format.channelCount),
                                       duration: Double(file.length) / format.sampleRate, frameLength: file.length)
        } catch let error as CLIAudioError {
            throw error
        } catch {
            throw CLIAudioError.cannotOpenInput(error.localizedDescription)
        }
    }

    @discardableResult
    public func convert(
        inputURL: URL,
        outputURL: URL,
        configuration: CLIAudioConfiguration = CLIAudioConfiguration(),
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil,
        overwrite: Bool = false
    ) throws -> CLIAudioDescription {
        guard outputURL.pathExtension.lowercased() == "mp3" else {
            throw CLIAudioError.unsupportedFormat("输出文件必须使用 .mp3 扩展名")
        }
        if FileManager.default.fileExists(atPath: outputURL.path), !overwrite {
            throw CLIAudioError.cannotCreateOutput("输出文件已存在，不会覆盖：\(outputURL.lastPathComponent)")
        }
        if isCancelled?() == true { throw CLIAudioError.cancelled }
        let source = try inspect(inputURL)
        let parent = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw CLIAudioError.cannotCreateOutput(error.localizedDescription)
        }

        let tempURL = parent.appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        do {
            let inputFile = try AVAudioFile(forReading: inputURL)
            guard let flags = lame_init() else { throw CLIAudioError.encoder("LAME 初始化失败") }
            defer { lame_close(flags) }
            guard lame_set_in_samplerate(flags, Int32(source.sampleRate.rounded())) == 0,
                  lame_set_out_samplerate(flags, Int32(source.sampleRate.rounded())) == 0,
                  lame_set_num_channels(flags, Int32(source.channelCount)) == 0 else {
                throw CLIAudioError.encoder("无法设置采样率或声道数")
            }
            let mode = source.channelCount == 1 ? MONO : (configuration.fullStereo ? STEREO : JOINT_STEREO)
            guard lame_set_mode(flags, mode) == 0,
                  lame_set_VBR(flags, vbr_default) == 0,
                  lame_set_VBR_q(flags, Int32(configuration.vbrQuality)) == 0 else {
                throw CLIAudioError.encoder("无法设置 LAME 参数")
            }
            lame_set_write_id3tag_automatic(flags, 0)
            let initResult = lame_init_params(flags)
            guard initResult >= 0 else { throw CLIAudioError.encoder("LAME 参数初始化失败 (\(initResult))") }

            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: tempURL)
            defer { try? handle.close() }
            let chunkSize: AVAudioFrameCount = 8192
            guard let buffer = AVAudioPCMBuffer(pcmFormat: inputFile.processingFormat, frameCapacity: chunkSize) else {
                throw CLIAudioError.invalidAudio("无法分配 PCM 缓冲区")
            }
            var processed: AVAudioFramePosition = 0
            while inputFile.framePosition < inputFile.length {
                if isCancelled?() == true { throw CLIAudioError.cancelled }
                let remaining = inputFile.length - inputFile.framePosition
                buffer.frameLength = min(chunkSize, AVAudioFrameCount(remaining))
                try inputFile.read(into: buffer, frameCount: buffer.frameLength)
                guard buffer.frameLength > 0 else { break }
                var encoded = [UInt8](repeating: 0, count: max(16_384, Int(buffer.frameLength) * 5 / 4 + 7_200))
                let written: Int32
                if source.channelCount == 1 {
                    guard let channel = buffer.floatChannelData?.pointee else { throw CLIAudioError.invalidAudio("无法读取单声道 PCM") }
                    written = lame_encode_buffer_ieee_float(flags, channel, channel, Int32(buffer.frameLength), &encoded, Int32(encoded.count))
                } else if buffer.format.isInterleaved {
                    guard let samples = buffer.floatChannelData?.pointee else { throw CLIAudioError.invalidAudio("无法读取交织 PCM") }
                    written = lame_encode_buffer_interleaved_ieee_float(flags, samples, Int32(buffer.frameLength), &encoded, Int32(encoded.count))
                } else {
                    guard let channels = buffer.floatChannelData else { throw CLIAudioError.invalidAudio("无法读取双声道 PCM") }
                    written = lame_encode_buffer_ieee_float(flags, channels[0], channels[1], Int32(buffer.frameLength), &encoded, Int32(encoded.count))
                }
                guard written >= 0 else { throw CLIAudioError.encoder("PCM 编码失败 (\(written))") }
                try handle.write(contentsOf: Data(encoded.prefix(Int(written))))
                processed += AVAudioFramePosition(buffer.frameLength)
                progress?(min(0.99, Double(processed) / Double(source.frameLength)))
            }
            var flush = [UInt8](repeating: 0, count: 7_200)
            let flushed = lame_encode_flush(flags, &flush, Int32(flush.count))
            guard flushed >= 0 else { throw CLIAudioError.encoder("编码刷新失败 (\(flushed))") }
            try handle.write(contentsOf: Data(flush.prefix(Int(flushed))))
            try handle.synchronize()
        } catch let error as CLIAudioError {
            throw error
        } catch {
            throw CLIAudioError.cannotCreateOutput(error.localizedDescription)
        }

        let output = try inspectOutput(tempURL)
        guard output.channelCount == source.channelCount,
              abs(output.sampleRate - source.sampleRate) < 1,
              abs(output.duration - source.duration) <= 0.1 else {
            throw CLIAudioError.validationFailed("输出技术参数与源文件不匹配")
        }
        do {
            if overwrite, FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
            } else {
                guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                    throw CLIAudioError.cannotCreateOutput("输出文件已存在，不会覆盖：\(outputURL.lastPathComponent)")
                }
                guard link(tempURL.path, outputURL.path) == 0 else {
                    throw CLIAudioError.cannotCreateOutput(String(cString: strerror(errno)))
                }
                try? FileManager.default.removeItem(at: tempURL)
            }
        } catch let error as CLIAudioError {
            throw error
        } catch {
            throw CLIAudioError.cannotCreateOutput(error.localizedDescription)
        }
        progress?(1)
        return output
    }

    private func inspectOutput(_ url: URL) throws -> CLIAudioDescription {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else {
                throw CLIAudioError.invalidAudio("输出 PCM 信息为空")
            }
            return CLIAudioDescription(sampleRate: format.sampleRate, channelCount: Int(format.channelCount),
                                       duration: Double(file.length) / format.sampleRate, frameLength: file.length)
        } catch let error as CLIAudioError {
            throw error
        } catch {
            throw CLIAudioError.validationFailed(error.localizedDescription)
        }
    }
}
