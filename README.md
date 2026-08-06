# READ3-IOS

READ3-IOS 的目标是使用原生 Swift 重写一款兼容 Legado／阅读 3.0 书源格式的 iOS 阅读器。

当前仓库处于项目初始化阶段，尚未实现书源兼容、搜索、目录、正文获取或实际阅读器功能。

## 仓库结构

- `Packages/LegadoCore`：可在 Windows 和 macOS 上构建、测试的跨平台核心包。
- `Apple/LegadoIOS`：需要通过 macOS、Xcode 和 Apple SDK 构建的 iOS 应用代码。
- `Reference/READ3.0`：只读 Android 参考仓库，仅用于分析可观察行为和数据格式。
- `TestSources`：后续存放确定性兼容测试夹具。

Windows 用于开发和测试 `LegadoCore`：

```powershell
swift test --package-path Packages/LegadoCore
```

iOS 应用由 macOS CI 使用 Xcode 构建。Windows 上的 Swift 测试不能替代 Xcode 构建验证。

克隆仓库后初始化 Android 参考子模块：

```powershell
git submodule update --init --recursive
```
