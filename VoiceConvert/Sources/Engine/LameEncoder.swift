import Foundation

public enum LameError: LocalizedError {
    case initFailed
    case invalidParameters(String)
    case setParamsFailed(Int32)
    case encodeFailed(Int32)
    case flushFailed(Int32)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .initFailed: return "LAME 编码器初始化失败"
        case .invalidParameters(let reason): return "LAME 参数无效：\(reason)"
        case .setParamsFailed(let code): return "LAME 参数设置失败 (\(code))"
        case .encodeFailed(let code): return "LAME 数据编码失败 (\(code))"
        case .flushFailed(let code): return "LAME 刷新缓冲区失败 (\(code))"
        case .cancelled: return "转换已被取消"
        }
    }
}

public final class LameEncoder {
    private var lameFlags: lame_t?
    private let outBufferSize: Int = 16384
    private var isConfigured = false

    public init() throws {
        guard let flags = lame_init() else {
            throw LameError.initFailed
        }
        self.lameFlags = flags
    }

    deinit {
        if let flags = lameFlags {
            lame_close(flags)
        }
    }

    public func configure(
        sampleRate: Int32,
        channels: Int32,
        vbrQuality: VBRQuality,
        fullStereo: Bool
    ) throws {
        guard let flags = lameFlags else { throw LameError.initFailed }
        guard (8_000...48_000).contains(sampleRate), [1, 2].contains(channels) else {
            throw LameError.invalidParameters("采样率或声道数不受支持")
        }

        guard lame_set_in_samplerate(flags, sampleRate) == 0,
              lame_set_out_samplerate(flags, sampleRate) == 0,
              lame_set_num_channels(flags, channels) == 0 else {
            throw LameError.invalidParameters("无法设置采样率或声道数")
        }

        if channels == 1 {
            guard lame_set_mode(flags, MONO) == 0 else { throw LameError.invalidParameters("无法设置单声道模式") }
        } else {
            let mode = fullStereo ? STEREO : JOINT_STEREO
            guard lame_set_mode(flags, mode) == 0 else { throw LameError.invalidParameters("无法设置立体声模式") }
        }

        guard lame_set_VBR(flags, vbr_default) == 0,
              lame_set_VBR_q(flags, Int32(vbrQuality.rawValue)) == 0 else {
            throw LameError.invalidParameters("无法设置编码质量")
        }
        lame_set_write_id3tag_automatic(flags, 0)
        let result = lame_init_params(flags)
        if result < 0 {
            throw LameError.setParamsFailed(result)
        }
        isConfigured = true
    }

    public func encode(interleavedPcm: [Float], numberOfSamplesPerChannel: Int) throws -> Data {
        guard let flags = lameFlags, isConfigured else { throw LameError.initFailed }
        guard numberOfSamplesPerChannel >= 0,
              numberOfSamplesPerChannel <= interleavedPcm.count / 2,
              numberOfSamplesPerChannel <= Int(Int32.max),
              interleavedPcm.count <= Int(Int32.max) else {
            throw LameError.invalidParameters("PCM 样本数量无效")
        }
        var mp3Buffer = [UInt8](repeating: 0, count: max(outBufferSize, numberOfSamplesPerChannel * 5 / 4 + 7200))
        
        let bytesWritten = interleavedPcm.withUnsafeBufferPointer { pcmPtr -> Int32 in
            lame_encode_buffer_interleaved_ieee_float(
                flags,
                pcmPtr.baseAddress,
                Int32(numberOfSamplesPerChannel),
                &mp3Buffer,
                Int32(mp3Buffer.count)
            )
        }

        if bytesWritten < 0 {
            throw LameError.encodeFailed(bytesWritten)
        }

        return Data(mp3Buffer.prefix(Int(bytesWritten)))
    }

    public func encode(pcmLeft: [Float], pcmRight: [Float], numberOfSamples: Int) throws -> Data {
        guard let flags = lameFlags, isConfigured else { throw LameError.initFailed }
        guard numberOfSamples >= 0,
              numberOfSamples <= pcmLeft.count,
              numberOfSamples <= pcmRight.count,
              numberOfSamples <= Int(Int32.max) else {
            throw LameError.invalidParameters("PCM 样本数量无效")
        }
        var mp3Buffer = [UInt8](repeating: 0, count: max(outBufferSize, numberOfSamples * 5 / 4 + 7200))

        let bytesWritten = pcmLeft.withUnsafeBufferPointer { leftPtr -> Int32 in
            pcmRight.withUnsafeBufferPointer { rightPtr -> Int32 in
                lame_encode_buffer_ieee_float(
                    flags,
                    leftPtr.baseAddress,
                    rightPtr.baseAddress,
                    Int32(numberOfSamples),
                    &mp3Buffer,
                    Int32(mp3Buffer.count)
                )
            }
        }

        if bytesWritten < 0 {
            throw LameError.encodeFailed(bytesWritten)
        }

        return Data(mp3Buffer.prefix(Int(bytesWritten)))
    }

    public func flush() throws -> Data {
        guard let flags = lameFlags, isConfigured else { throw LameError.initFailed }
        var mp3Buffer = [UInt8](repeating: 0, count: 7200)

        let bytesWritten = lame_encode_flush(flags, &mp3Buffer, Int32(mp3Buffer.count))
        if bytesWritten < 0 {
            throw LameError.flushFailed(bytesWritten)
        }

        return Data(mp3Buffer.prefix(Int(bytesWritten)))
    }
}
