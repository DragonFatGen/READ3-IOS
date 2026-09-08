# READ3-IOS

READ3-IOS 的目标是使用原生 Swift 重写一款兼容 Legado／阅读 3.0 书源格式的 iOS 阅读器。

当前仓库已经实现可测试的书源模型、常用规则解析、HTTP 请求以及
`Search → BookInfo → TOC → Content` 核心链路，并包含原生 iOS 阅读界面。
兼容范围以测试和文档中列出的常用 Legado 语义为准，不代表完整兼容所有书源。

## 仓库结构

- `Packages/LegadoCore`：可在 Windows 和 macOS 上构建、测试的跨平台核心包。
- `Apple/LegadoIOS`：需要通过 macOS、Xcode 和 Apple SDK 构建的 iOS 应用代码。
- `Reference/READ3.0`：只读 Android 参考仓库，仅用于分析可观察行为和数据格式。
- `TestSources`：存放确定性的脱敏兼容测试夹具。

可以手动诊断一个本地书源文件：

```powershell
swift run --package-path Packages/LegadoCore legado-compatibility `
  --source .\my-source.json `
  --keyword "三体"
```

该命令会真实访问书源网站，仅用于手动诊断，不属于 CI 的联网测试。详细说明见
[`docs/live-source-compatibility-cli.md`](docs/live-source-compatibility-cli.md)。

Windows 用于开发和测试 `LegadoCore`：

```powershell
swift test --package-path Packages/LegadoCore
```

iOS 应用由 macOS CI 使用 Xcode 构建。Windows 上的 Swift 测试不能替代 Xcode 构建验证。

克隆仓库后初始化 Android 参考子模块：

```powershell
git submodule update --init --recursive
```
