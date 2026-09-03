# Third-party provenance

本文件记录当前发布包中 LAME/mpg123 二进制的可复核来源。来源证据在 2026-09-03 的 macOS arm64 环境核对，Homebrew formula commit 为 `7079a177935a240e5c2f21060a70791eb43633e0`。

| Component | Version | License | Upstream source | Source SHA-256 | Homebrew arm64_tahoe bottle SHA-256 |
| --- | --- | --- | --- | --- | --- |
| LAME | 4.0 | LGPL-2.0-or-later | https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz | `3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb` | `b0fe0cfb39c74a53b7635833fe3293a62c886b084bc5ccc8ed7cd177803182e4` |
| mpg123 | 1.33.7 | LGPL-2.1-only | https://www.mpg123.de/download/mpg123-1.33.7.tar.bz2 | `31d0e35a4ca567ec9b5ebda6c3062bb4435d6d3eacd6ef0d95cadd7854dc03ee` | `acabaed07a2aa95e360e1047df604cb45845254f2ff136671b9fb0d4bafc69ce` |

## Repository artifact hashes

这些是仓库当前实际文件的 SHA-256：

- `ThirdParty/lib/libmp3lame.a`: `59dc2c06d13adde86ccada8c167f50c52a382d46e5be440abcdce8738158432d`
- `ThirdParty/lib/libmpg123.a`: `e1e38d49d412c4ccd479a0b6a4a49b281e5282b765dec72220f14a0d42656c85`
- `ThirdParty/lib/libmp3lame.dylib`: `021938e62a4747c402d759f6528858ac30cb91aed267957a94b055ee983d9155`
- `ThirdParty/lib/libmpg123.dylib`: `cec4c49e9f5a803775bcf34447ad573dcf37608ab5dc5df4f93f0e1361ba5486`
- `ThirdParty/include/lame/lame.h`: `46eb6a9f0ec2186bfbf1c2455c9a667343b57e5ea53f87add97153568210b4dc`
- `ThirdParty/include/mpg123/mpg123.h`: `d6c7d5094aef2f6587819b4445028c45f06af26b15a5fb643a55c4be09cf7c4a`

静态库与对应 Homebrew Cellar 产物逐字节一致；App 使用的动态库导出符号一致，且为适配 App bundle 将 install name 改为 `@rpath`。CLI 当前仍静态链接，LGPL 对静态链接的对象文件/可重链接义务需要项目所有者或法律顾问确认。
