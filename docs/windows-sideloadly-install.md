# Windows 上通过 Sideloadly 安装 READ3-IOS（未签名 IPA）

本文档说明如何安装 GitHub Actions 工作流 **iOS Device IPA** 打包的未签名 IPA。
该 IPA 由 CI 在 macOS runner 上用真机 SDK（iphoneos / arm64 / Release）编译，
**不包含任何签名**。签名在你的 Windows 电脑上由 Sideloadly 完成，
GitHub 和本仓库不收集 Apple 账号密码、验证码、证书或私钥。

## 1. 下载 IPA

1. 打开仓库的 **Actions** 页面，选择左侧的 **iOS Device IPA** 工作流。
2. 点击你想要安装的这一次运行记录。
3. 在页面底部的 **Artifacts** 中下载 `READ3-IOS-unsigned`。
4. 解压得到的 zip，里面是一个标准结构的 IPA 文件 `READ3-IOS-unsigned.ipa`（本质是 zip，包含 `Payload/LegadoIOS.app`）。
5. Artifacts 只保留 7 天，过期后需要在 Actions 页面手动重新运行一次该工作流。

## 2. 安装 Sideloadly

1. 访问 Sideloadly 官网 <https://sideloadly.io/>，下载并安装 **Windows 版**。
2. 按官网要求准备 Apple 驱动及依赖。通常需要：
   - 从 Microsoft Store 安装 Apple 提供的 **Apple Devices**（或 **iTunes**，官网会说明当前要求的版本）；
   - 安装 **iCloud**（Windows 版，同样以官网要求为准）。
3. 具体驱动和软件版本要求可能随时间变化，始终以 Sideloadly 官网当前文档为准。

## 3. 连接 iPhone 并安装

1. 用 USB 线将 iPhone 连接到 Windows 电脑。
2. 解锁 iPhone，并在弹出的提示中选择 **信任此电脑**（如要求，输入锁屏密码）。
3. 打开 Sideloadly，它会识别已连接的设备；在设备列表中选择你的 iPhone。
4. 将 `READ3-IOS-unsigned.ipa` 拖入（或选择）IPA 栏。
5. 在 Apple ID 栏填入 **你自己的 Apple 账号**，点击开始安装。
   - Sideloadly 会用这个账号对应用做个人签名。不要把账号密码发给任何人，也不要把它配置到 GitHub。
   - 若账号开启双重认证，按提示在 Sideloadly 中输入验证码即可。
6. 等待安装完成，iPhone 桌面上会出现 READ3-IOS 的图标。

## 4. 信任开发者并启动

1. 首次打开应用时，iPhone 会提示“未受信任的开发者”。
2. 进入 **设置 → 通用 → VPN与设备管理**（或“描述文件与设备管理”），
   找到你的 Apple 账号对应的开发者条目，选择 **信任**。
3. iOS 16 及更高版本还需要开启开发者模式：
   **设置 → 隐私与安全性 → 开发者模式**，打开后按提示重启设备。
4. 再次点击应用图标即可启动。

## 5. 免费签名的有效期与更新

- 使用免费（个人）Apple 账号签名时，应用证书有效期通常为 **7 天**，
  到期后应用会无法打开（图标变灰或闪退）。
- 续期方式：重新连接 iPhone，用 Sideloadly 和 **同一个 Apple 账号** 重新安装一次
  （部分版本的 Sideloadly 提供一键刷新功能，以官网说明为准）。
- **更新应用时务必使用同一个 Apple 账号，且保持 Bundle Identifier 不变**
  （当前为 `com.read3.legadoios`），这样新安装会覆盖旧版本，书架、阅读进度等本地数据得以保留。
- **不要先卸载再安装**，卸载会删除应用数据。

## 6. 已知限制

- 免费签名同一时间可签名的应用数量有限（通常为 3 个），且每 7 天需要刷新。
- 应用声明了音频后台模式（`UIBackgroundModes: audio`，用于朗读功能）。
  该声明不需要付费证书即可安装；后台行为以 iOS 实际策略为准。
- 应用不包含任何书源、小说内容或私人数据；书源需安装后在应用内自行导入。
