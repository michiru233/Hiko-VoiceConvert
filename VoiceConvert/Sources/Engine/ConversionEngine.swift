import Foundation
import AVFoundation
import Darwin

public struct AudioDescription: Equatable, Sendable {
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

public enum ConversionError: LocalizedError, Equatable {
    case unsupportedFormat(String)
    case cannotOpenInput(String)
    case cannotCreateOutput(String)
    case invalidAudio(String)
    case validationFailed(String)
    case cancelled
    case encoder(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): return "不支持的音频格式：\(ext)"
        case .cannotOpenInput(let reason): return "无法读取输入音频：\(reason)"
        case .cannotCreateOutput(let reason): return "无法创建输出文件：\(reason)"
        case .invalidAudio(let reason): return "音频数据无效：\(reason)"
        case .validationFailed(let reason): return "输出校验失败：\(reason)"
        case .cancelled: return "转换已取消"
        case .encoder(let reason): return "编码失败：\(reason)"
        }
    }
}

public struct ConversionResult: Equatable, Sendable {
    public let inputURL: URL
    public let outputURL: URL
    public let source: AudioDescription
    public let output: AudioDescription

    public init(inputURL: URL, outputURL: URL, source: AudioDescription, output: AudioDescription) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.source = source
        self.output = output
    }
}

public final class ConversionEngine: @unchecked Sendable {
    public static let supportedExtensions: Set<String> = ["wav", "flac", "aiff", "aif", "m4a"]

    public init() {}

    public func inspect(_ inputURL: URL) throws -> AudioDescription {
        guard Self.supportedExtensions.contains(inputURL.pathExtension.lowercased()) else {
            throw ConversionError.unsupportedFormat(inputURL.pathExtension)
        }
        do {
            let file = try AVAudioFile(forReading: inputURL)
            let format = file.processingFormat
            guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else {
                throw ConversionError.invalidAudio("采样率、声道数或时长为空")
            }
            return AudioDescription(
                sampleRate: format.sampleRate,
                channelCount: Int(format.channelCount),
                duration: Double(file.length) / format.sampleRate,
                frameLength: file.length
            )
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.cannotOpenInput(error.localizedDescription)
        }
    }

    @discardableResult
    public func convert(
        inputURL: URL,
        outputURL: URL,
        config: ConversionConfig = ConversionConfig(),
        progress: (@Sendable (Double) -> Void)? = nil,
        isCancelled: (@Sendable () -> Bool)? = nil,
        overwrite: Bool = false
    ) throws -> ConversionResult {
        guard outputURL.pathExtension.lowercased() == "mp3" else {
            throw ConversionError.unsupportedFormat("输出文件必须使用 .mp3 扩展名")
        }
        if FileManager.default.fileExists(atPath: outputURL.path), !overwrite {
            throw ConversionError.cannotCreateOutput("输出文件已存在，不会覆盖：\(outputURL.lastPathComponent)")
        }
        if isCancelled?() == true { throw ConversionError.cancelled }
        let source = try inspect(inputURL)
        guard source.channelCount <= 2 else {
            throw ConversionError.invalidAudio("仅支持单声道或双声道输入")
        }

        let parent = outputURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        } catch {
            throw ConversionError.cannotCreateOutput(error.localizedDescription)
        }

        let tempURL = parent.appendingPathComponent(".\(outputURL.lastPathComponent).\(UUID().uuidString).tmp")
        defer {
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        do {
            let inputFile = try AVAudioFile(forReading: inputURL)
            let encoder = try LameEncoder()
            try encoder.configure(
                sampleRate: Int32(source.sampleRate.rounded()),
                channels: Int32(source.channelCount),
                vbrQuality: config.vbrQuality,
                fullStereo: config.fullStereo
            )

            FileManager.default.createFile(atPath: tempURL.path, contents: nil)
            guard let handle = try? FileHandle(forWritingTo: tempURL) else {
                throw ConversionError.cannotCreateOutput("无法打开临时输出文件")
            }
            defer { try? handle.close() }

            let chunkSize: AVAudioFrameCount = 8192
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: inputFile.processingFormat,
                frameCapacity: chunkSize
            ) else {
                throw ConversionError.invalidAudio("无法分配 PCM 缓冲区")
            }

            var processedFrames: AVAudioFramePosition = 0
            while inputFile.framePosition < inputFile.length {
                if isCancelled?() == true { throw ConversionError.cancelled }
                let remaining = inputFile.length - inputFile.framePosition
                guard remaining > 0, remaining <= AVAudioFramePosition(AVAudioFrameCount.max) else {
                    throw ConversionError.invalidAudio("音频帧数超出支持范围")
                }
                buffer.frameLength = min(chunkSize, AVAudioFrameCount(remaining))
                try inputFile.read(into: buffer, frameCount: buffer.frameLength)
                guard buffer.frameLength > 0 else { break }

                let encoded: Data
                if source.channelCount == 1 {
                    guard let channel = buffer.floatChannelData?.pointee else {
                        throw ConversionError.invalidAudio("无法读取单声道 PCM 数据")
                    }
                    let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
                    encoded = try encoder.encode(pcmLeft: samples, pcmRight: samples, numberOfSamples: samples.count)
                } else if buffer.format.isInterleaved {
                    guard let interleaved = buffer.floatChannelData?.pointee else {
                        throw ConversionError.invalidAudio("无法读取交织 PCM 数据")
                    }
                    let sampleCount = Int(buffer.frameLength) * source.channelCount
                    let samples = Array(UnsafeBufferPointer(start: interleaved, count: sampleCount))
                    encoded = try encoder.encode(interleavedPcm: samples, numberOfSamplesPerChannel: Int(buffer.frameLength))
                } else {
                    guard let channels = buffer.floatChannelData else {
                        throw ConversionError.invalidAudio("无法读取双声道 PCM 数据")
                    }
                    let left = channels[0]
                    let right = channels[1]
                    let count = Int(buffer.frameLength)
                    let leftSamples = Array(UnsafeBufferPointer(start: left, count: count))
                    let rightSamples = Array(UnsafeBufferPointer(start: right, count: count))
                    encoded = try encoder.encode(pcmLeft: leftSamples, pcmRight: rightSamples, numberOfSamples: count)
                }
                try handle.write(contentsOf: encoded)
                processedFrames += AVAudioFramePosition(buffer.frameLength)
                progress?(min(0.99, Double(processedFrames) / Double(source.frameLength)))
            }

            if isCancelled?() == true { throw ConversionError.cancelled }
            try handle.write(contentsOf: encoder.flush())
            try handle.synchronize()
        } catch let error as ConversionError {
            throw error
        } catch let error as LameError {
            throw ConversionError.encoder(error.localizedDescription)
        } catch {
            throw ConversionError.cannotCreateOutput(error.localizedDescription)
        }

        guard FileManager.default.fileExists(atPath: tempURL.path) else {
            throw ConversionError.cannotCreateOutput("临时输出不存在")
        }
        let outputDescription: AudioDescription
        do {
            outputDescription = try inspectOutput(tempURL)
        } catch {
            throw ConversionError.validationFailed(error.localizedDescription)
        }
        let durationError = abs(outputDescription.duration - source.duration)
        guard outputDescription.channelCount == source.channelCount else {
            throw ConversionError.validationFailed("声道数不一致：源 \(source.channelCount)，输出 \(outputDescription.channelCount)")
        }
        guard abs(outputDescription.sampleRate - source.sampleRate) < 1 else {
            throw ConversionError.validationFailed("采样率不一致：源 \(source.sampleRate)，输出 \(outputDescription.sampleRate)")
        }
        guard durationError <= 0.1 else {
            throw ConversionError.validationFailed("时长误差超过 0.1 秒：\(durationError)")
        }

        do {
            if overwrite, FileManager.default.fileExists(atPath: outputURL.path) {
                _ = try FileManager.default.replaceItemAt(outputURL, withItemAt: tempURL)
            } else {
                guard !FileManager.default.fileExists(atPath: outputURL.path) else {
                    throw ConversionError.cannotCreateOutput("输出文件已存在，不会覆盖：\(outputURL.lastPathComponent)")
                }
                try publishWithoutReplacement(tempURL: tempURL, outputURL: outputURL)
            }
        } catch let error as ConversionError {
            throw error
        } catch {
            throw ConversionError.cannotCreateOutput(error.localizedDescription)
        }
        progress?(1.0)
        return ConversionResult(inputURL: inputURL, outputURL: outputURL, source: source, output: outputDescription)
    }

    private func publishWithoutReplacement(tempURL: URL, outputURL: URL) throws {
        let result = link(tempURL.path, outputURL.path)
        guard result == 0 else {
            let code = errno
            if code == EEXIST || code == ENOTEMPTY {
                throw ConversionError.cannotCreateOutput("输出文件已存在，不会覆盖：\(outputURL.lastPathComponent)")
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))])
        }
        do {
            try FileManager.default.removeItem(at: tempURL)
        } catch {
            // Publishing already succeeded; the outer cleanup will retry the hidden temp file.
        }
    }

    private func inspectOutput(_ url: URL) throws -> AudioDescription {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0, file.length > 0 else {
            throw ConversionError.invalidAudio("输出 PCM 信息为空")
        }
        return AudioDescription(
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            duration: Double(file.length) / format.sampleRate,
            frameLength: file.length
        )
    }
}
