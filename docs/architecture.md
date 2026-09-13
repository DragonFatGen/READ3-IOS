# Architecture

本项目将跨平台核心逻辑和 Apple 平台实现明确分层。

`Packages/LegadoCore` 是跨平台核心层。它需要在 Windows 和 macOS 上构建并运行测试，不依赖 SwiftUI、UIKit、WebKit、JavaScriptCore、AVFoundation 等 Apple 专属框架。

`Apple/LegadoIOS` 是 Apple 专属实现层，用于 SwiftUI 应用及后续需要 Apple SDK 的功能。该层必须通过 macOS 上的 Xcode 构建验证。

`Reference/READ3.0` 中的 Android 项目只用于分析可观察行为和数据格式，保持只读，不作为机械移植的代码来源。

Windows 上的 `LegadoCore` 测试只能验证跨平台代码，不能替代 macOS CI 或 Xcode 对 iOS 应用的构建验证。

后续工作将按数据模型、规则解析、规则执行、网络抽象和 UI 的顺序分阶段推进，并为每个阶段补充确定性测试。

## iOS 阅读流程检查与验收

本轮背景证据由用户提供：[真实书源诊断 34751929737](https://github.com/DragonFatGen/READ3-IOS/actions/runs/34751929737)，
提交 `b4e2b64`，Windows/macOS 均获得 1 本搜索结果、743 条目录和所选章节 3021 字符正文。
这是单个书源、单本书、所选章节的 Core CLI 证据，不是 iOS 界面或持久化验收结果。
本轮没有运行 Swift/Xcode、模拟器、真机或联网诊断，也没有访问书源 Secret。

### 调用链和发现的缺口

以下文件均位于 `Apple/LegadoIOS`；未列为修复的已实现行为保持原结构。

| 环节 | 现有实现和本轮处理 |
| --- | --- |
| 导入 | `Features/Sources/SourceListView.swift` 的“导入”通过 `.fileImporter` 读取 JSON，进入 `BookSourceStore.importSources`，复用 Core importer。单对象和数组均可导入，按书源 URL 更新并写入 UserDefaults；没有新增导入入口。 |
| 搜索 | `SearchView` 的 Picker 调用 `SearchViewModel.selectSource`，`search` 捕获选中书源，再由 `LegadoSearchService` 调用 Core。原 `cancelSearch` 仅取消任务，未结束加载状态；现在同步清除 requestID 和 loading，防止旧任务影响新选择。 |
| 详情 | 搜索行把书源和结果传给 `BookDetailView`，`BookDetailViewModel` 通过 `LegadoBookInfoService` 获取详情。已有 requestID 与取消检查、加载提示和重试，保留实现。 |
| 书架 | `LibraryRepository.add` 使用“书源 URL + 书籍 URL”作为身份，重复添加更新现有记录并保留进度。新增分支原来没有继承先阅读、后入架的进度；现从独立进度表接回 progress 和 lastReadAt。 |
| 目录 | 详情进入 `TOCView`，卷标题不可点击，章节行把选中索引传给 Reader。`BookshelfView` 的继续阅读路径按章节 URL 优先恢复、索引兜底，现在从 repository 读取最新进度；空目录或仅卷标题时可重试。 |
| 正文 | `ReaderViewModel` 原上下章、初始索引和预加载可能选中卷标题；现在跳过卷标题，仍保留原始目录索引。现有请求 ID、章节 URL 和取消检查保护正文及分页不被旧结果覆盖。 |
| 进度 | `ReadingProgress` 保存章节 URL、名称、目录索引、章节内归一化比例、目录总数和时间。Reader 700ms 防抖，离开阅读器、场景离开 active 和切章时刷新。原来失败章节退出也会覆盖旧进度；现只保存已有正文的章节。 |
| 恢复位置 | 原 `matches` 在 URL 不同但索引相同时仍恢复比例；现非空 URL 优先，只有旧记录 URL 为空才按索引匹配。原滚动恢复重复消费后默认跳顶部，且恢复距离与保存距离不一致；现只消费一次、等待布局尺寸，并统一采用完整内容的可滚动距离。 |

搜索空结果、详情/目录/正文加载中与失败提示沿用现有 `StatusView`/`ProgressView`；失败后可重试。
正文主动刷新时原有内容分支会遮住错误；现在保留正文视图及位置，同时展示刷新加载或失败提示。
重试沿用失败请求的缓存策略，主动刷新失败后的重试不会悄悄回到缓存读取。
目录 URL 已消失时继续阅读仍按范围内索引选择附近章节，但不会将其他 URL 的旧章节内比例套用到新章节。
进度仍是近似比例而不是字符级书签：滚动定位沿用 1% 锚点，分页沿用页比例；改变字号、布局或网站正文后不承诺精确到同一字符。
目录总数包含卷标题，未改变现有全书百分比定义。书架恢复仍需加载目录；缓存正文不等于全书离线可用。

### 云端离线验证

现有 `project.yml` 把整个 `Apple/LegadoIOSTests` 目录加入 `LegadoIOSTests`，并加入
`LegadoIOS` scheme 的 test targets，因此新增文件无需单独枚举。
没有现成 XCUITest 目标，本轮不新增 UI 测试框架。

- `OfflineReadingFlowTests`：合成单书源 JSON → 导入并重建书源存储 → 切换选中书源 →
  实际 Core 搜索、详情、目录、正文适配器 → 书架去重 → 切章 → 保存 → 新 UserDefaults/
  repository/Reader 实例恢复。HTTP 客户端只返回内存合成 HTML，不调用网络；临时存储测试结束清理。
- `LibraryRepositoryTests`：先阅读后入架、重复入架及存储重载；保留原有去重和持久化用例。
- `SearchViewModelTests`、`ReaderViewModelTests`：旧服务忽略取消后才返回、切换书源/章节、
  错误重试、失败章节不覆盖进度、卷标题跳过、章节身份匹配和恢复值只消费一次。
- `BookDetailViewModelTests`、`TOCViewModelTests`：实际从失败重试到成功。
- `ReaderScrollMetricsTests`：保存比例与恢复偏移使用相同可滚动范围，短正文及边界值处理。

`.github/workflows/ios-build.yml` 已有真正的 `xcodebuild ... test`，未使用
`build-for-testing` 冒充执行；本轮将步骤名称改为完整 iOS 单元测试，并输出
`TestResults/LegadoIOS.xcresult`、上传 `ios-test-results`。云端应检查新增测试的执行数量、失败及跳过情况，
不能仅凭前面的 simulator `build` 成功判断。Core Tests 仍在 Windows/macOS 执行，但不包含 Apple 测试。
测试不依赖真实站点、凭证或 Secret；构建依赖下载与模拟器环境仍由 CI 提供。
本轮新增用例尚未执行，待提交由用户推送后通过 Actions 验证；本轮不自动推送或 dispatch。

### 实际启动前提

仓库提供的是 XcodeGen 项目定义，没有现成的 iPhone 安装包、TestFlight 发布或签名设备构建工作流。
当前 iOS workflow 构建无签名 **simulator** 目标，只上传日志和测试结果，不上传 `.app` 或 `.ipa`。
它的构建成功不能解释成可以在 iPhone 上安装。

手动交互验收需要一台装有兼容 Swift 6 的 Xcode（如 Xcode 16 系列）、XcodeGen 和 iOS Simulator
runtime 的 Mac。取得待验收提交，在 Mac 的仓库根目录运行 `xcodegen generate`，用 Xcode 打开生成的
`LegadoIOS.xcodeproj`，选择 `LegadoIOS` scheme 和已安装的 iPhone 模拟器，再执行 Run。
项目最低 iOS 版本为 16.0。以上是 macOS 操作，不是 Windows 命令。
若要真机运行，另需 Xcode 中配置自己的开发团队、可用签名与设备授权；本轮没有配置或验证签名。
Windows 单独无法启动此 iOS 应用；仅有 Actions 日志也无法进行触摸交互验收。

### 手动验收清单（待执行）

在同一个安装实例上执行，记录提交、Xcode/iOS 版本、模拟器型号或真机型号及实际结果。
由验收者自行准备合法可用的单个书源 JSON 文件，并放到设备/模拟器 Files 可访问的位置；
不从 GitHub Secret 提取，不提交书源文件、凭证或正文截图到仓库。使用标准 JSON 请求选项，
保持已验证的解析规则不变；不使用“测试全部”扩大书源范围。

1. **导入**：打开“书源”→“导入”，在系统文件选择器选择 JSON；应显示书源名称并可进入搜索。
   重复导入同一书源应更新而非新增重复项；错误文件应有导入失败提示，可重新选择文件。
2. **搜索与详情**：进入该书源，核对“搜索书源”选择，输入关键词并搜索。
   检查加载、空结果状态；点击结果后核对书名、作者和来源，详情失败时点重试。
3. **入架**：点“加入书架”，重复点击后书架仍只有一条同源同书记录。
   此身份规则允许不同书源的同名书并存。
4. **目录与正文**：从详情“查看目录”选择一章，核对标题和正文；测试上下章、正文内“目录”跳章。
   如有卷标题，应跳过它，不作为正文请求。快速连续切章后，较早结果不能覆盖最后选择的章节。
5. **保存和再次打开**：在正文中滚动到约中部，记下章节名和进度，返回书架，点“继续阅读”。
   应恢复同一章及大致位置，不应先跳回顶部后覆盖已存进度。分页模式如需验收，可在既有阅读设置中切换后重复。
   补充验证“先从详情读书，再返回详情加入书架”，书架应显示已读章节及进度。
6. **重启**：返回书架或将应用置于后台，让正常生命周期保存完成；通过模拟器停止/重新启动应用
   或在设备关闭后重新打开，保留同一应用数据，不卸载、不清除存储。核对书源、书架和继续阅读位置。
   这不等同于验证断电或在尚未保存时强制杀进程的耐久性。
7. **失败与重试**：由验收者断网，或在可控测试环境令请求失败。已缓存正文可能继续可读，
   可用“更多阅读操作”→“重新加载本章”测试忽略缓存的请求，或尝试未缓存章节。
   检查错误提示、返回能力及原进度保留；恢复网络后重试，应显示正确章节。
   从书架打开时目录请求失败也应可重试；不会承诺断网时整条恢复链都可用。

以上步骤尚未在模拟器或真机执行。单元测试只能证明模型和存储数据流，不能证明系统文件选择器权限、
SwiftUI 导航、实际滚动布局或跨进程持久化已通过手动验收。
