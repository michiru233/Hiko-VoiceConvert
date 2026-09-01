# VoiceConvertCLI

`voiceconvert` 是“音声转换”的 SwiftPM 命令行入口，依赖同级的 `../VoiceConvertCore`，并静态链接仓库内 arm64 LAME/mpg123 音频后端。

## 构建与运行

```bash
swift build --package-path VoiceConvertCLI --product voiceconvert
swift run --package-path VoiceConvertCLI voiceconvert --help
```

## 命令

```bash
voiceconvert audio PATH... [--check] [--output DIR] [--policy suffix|skip|overwrite] [--yes]
voiceconvert subtitle PATH... [--speakers] [--strict]
voiceconvert pair AUDIO_PATH SUBTITLE_PATH [--output DIR] [--policy suffix|skip|overwrite] [--yes]
voiceconvert pair --audio PATH --subtitle PATH [--audio PATH --subtitle PATH ...]
voiceconvert --convert PATH [--speakers]
```

- `audio` 递归扫描 WAV、FLAC、AIFF/AIF、M4A，并使用 AVFoundation 解码和 LAME 编码生成可解码 MP3。默认输出到输入根的同级 `输入目录名-converted`，保留相对目录结构。
- `audio --check` 只执行输入预检，不生成文件。
- `subtitle` 递归转换 `.vtt` 为 UTF-8 无 BOM、LF 结尾的 LRC；已有输出默认不覆盖。`--strict` 启用严格 VTT 校验，`--speakers` 保留说话人前缀。
- `pair` 使用 Core 的大小写不敏感安全主干匹配和父/子任务执行器，生成同目录同主干的 MP3/LRC；`--no-mp3` 或 `--no-lrc` 可关闭一种输出。
- `suffix` 默认使用 `track (1).ext`，`skip` 保留已有文件并返回部分失败，`overwrite` 只有提供 `--yes` 才替换已有输出。
- 所有音频输出都会写入隐藏临时文件、重新由 AVFoundation 解码校验，然后原子发布；失败时清理临时文件并保留已有正式输出。

## 退出码

| Code | Meaning |
| --- | --- |
| 0 | 全部输入处理成功 |
| 1 | 部分失败、重复、未配对、跳过或转换失败 |
| 64 | 参数或子命令无效 |
| 66 | 没有可处理的输入 |
| 69 | 音频后端不可用（当前构建已包含后端，通常只用于环境/链接故障） |

CLI 只支持仓库声明的 arm64/macOS 26.0 目标。第三方许可证和来源说明见根目录 `NOTICE` 与 `ThirdParty/licenses/`。
