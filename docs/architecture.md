# Architecture

本项目将跨平台核心逻辑和 Apple 平台实现明确分层。

`Packages/LegadoCore` 是跨平台核心层。它需要在 Windows 和 macOS 上构建并运行测试，不依赖 SwiftUI、UIKit、WebKit、JavaScriptCore、AVFoundation 等 Apple 专属框架。

`Apple/LegadoIOS` 是 Apple 专属实现层，用于 SwiftUI 应用及后续需要 Apple SDK 的功能。该层必须通过 macOS 上的 Xcode 构建验证。

`Reference/READ3.0` 中的 Android 项目只用于分析可观察行为和数据格式，保持只读，不作为机械移植的代码来源。

Windows 上的 `LegadoCore` 测试只能验证跨平台代码，不能替代 macOS CI 或 Xcode 对 iOS 应用的构建验证。

后续工作将按数据模型、规则解析、规则执行、网络抽象和 UI 的顺序分阶段推进，并为每个阶段补充确定性测试。
