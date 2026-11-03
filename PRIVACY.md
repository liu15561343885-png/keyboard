# 隐私说明

PrivateKeyboard 的目标是：**输入内容、按键、上下文和个人词频不离开设备。**

## 数据流

```text
按键
  → Keyboard Extension（本机）
  → 本地拼音切分 / 本地词库 / 本地 LM / 本地 Core ML
  → 候选栏
  → 用户选择
  → App Group 中的本地词频/最近记录
```

```text
主 App（仅用户主动检查或启动自动检查时）
  → HTTPS GET 公开的 manifest.json
  → HTTPS GET 公开词库/模型文件
  → 校验大小 + SHA-256 + Ed25519
  → 原子写入 App Group
```

键盘扩展不链接、不调用 URLSession/URLRequest/WebSocket 等网络 API。主 App 的更新请求中只包含 manifest 和二进制文件 URL，不包含输入文本、按键、上下文、用户词频、广告标识符或崩溃数据。

## 本地保存了什么

| 数据 | 位置 | 用途 | 可否清除 |
|---|---|---|---|
| 用户词频 | App Group `user-history.json` | 候选排序 | 是 |
| 自定义词库 | App Group `user-lexicon.json` | 用户自定义候选 | 是 |
| 最近使用词条 | 同上 | 候选排序 | 是 |
| 键盘设置（声音/触感/模糊音） | App Group UserDefaults | 键盘行为 | 可重置 |
| 只读词库/模型 | Extension bundle + App Group 数据目录 | 输入与排序 | 随 App/版本删除 |
| 更新版本指针 | App Group `PrivateKeyboardDatasets/current.json` | 选择版本/回滚 | 随 App 删除 |

不保存完整输入历史，不把上下文写盘，不记录按键日志。`user-history.json`、数据集指针和数据集目录会设置 `isExcludedFromBackup`，避免被 iCloud/iTunes 备份静默带走；该设置是尽力而为，不替代系统级设备加密。

## 没有做什么

- 没有在线输入法 API；
- 没有远程翻译；
- 没有语音输入或语音模型；
- 没有广告 SDK；
- 没有第三方统计、归因、崩溃上报 SDK；
- 没有账户系统；
- 没有把用户词频同步到云端；
- 没有向第三方发送候选或词频。

Core ML 模型随 App 本地运行，使用 `.cpuOnly` 配置；模型不访问网络，不使用语音数据，不采集用户输入。

## 键盘完全访问

键盘 Info.plist 中 `RequestsOpenAccess = true`。键盘需要“允许完全访问”才能读取 App Group 中的共享词库、设置和用户词频；键盘扩展本身仍不包含网络代码，也不上传任何数据。如果你不需要 App Group 共享，可以把该值改回 `false`，键盘将只使用扩展 bundle 内置数据。

## 更新网络请求的边界

更新是唯一的网络行为，由主 App 发起：

- 请求公开的 `manifest.json` 和公开数据文件；
- 使用 HTTPS；
- 不携带用户 token、输入内容、设备标识或词频；
- 网络服务端可能看到常规的 IP、TLS 握手和请求时间等传输层信息。这是任何 HTTPS 请求都无法避免的，但本项目不额外发送个人数据。

## 清除个人数据

主 App → 本地数据 → **清除个人词库与词频**：

- 清空 `user-history.json` 和 `user-lexicon.json`；
- 内存中的当前输入法实例可能在下次键盘显示时刷新。

## 数据许可证与隐私的关系

内置词库是 CC-CEDICT、wordfreq、Tatoeba、jieba 等公开数据的派生二进制。它们不包含 PrivateKeyboard 用户的输入或个人词频。第三方数据许可证见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

## Apple 隐私清单

仓库包含 [Resources/PrivacyInfo.xcprivacy](Resources/PrivacyInfo.xcprivacy)，并同时复制到 Host App 与 Keyboard Extension：

- `NSPrivacyTracking = false`；
- `NSPrivacyTrackingDomains = []`；
- `NSPrivacyCollectedDataTypes = []`；
- 仅声明 `NSPrivacyAccessedAPICategoryUserDefaults`，原因 `CA92.1`（App 自身设置）和 `1C8F.1`（App Group 共享设置）。

App 与扩展的 bundle 还包含 `PRIVACY.md`、`THIRD_PARTY_LICENSES.md`、`LICENSE` 和 `licenses/` 全文，便于离线查阅。

## 安全报告

如果发现键盘扩展联网、用户文本落盘、manifest 校验绕过或其他隐私问题，请不要公开利用细节，先通过仓库 Security 联系人报告。参见 [SECURITY.md](SECURITY.md)。
