# PrivateKeyboard

一个完全离线的 iOS 中文输入法工程：SwiftUI 主 App、UIKit 键盘扩展、本地拼音引擎、本地中英双向词典、二元/三元语言模型、Core ML 微型候选排序，以及带 SHA-256 + Ed25519 校验的词库更新链路。

> **当前状态：Alpha 工程预览，不是“可日常使用”的版本。**
>
> 本项目不声称达到大厂输入法效果。核心库已经在本机（macOS / Swift 6.1）构建并通过端到端检查；UIKit/SwiftUI 源码已通过 Mac Catalyst SDK 类型检查，全部测试方法也已执行通过。但本机没有 iOS SDK / 完整 Xcode，因此 **尚未完成 iOS Simulator/真机构建**。GitHub Actions 已配置 iOS 构建与测试，需在 CI 或安装 Xcode 后完成最终验收。所有指标见 [docs/METRICS.md](docs/METRICS.md)。

## 已经落地的东西

| 能力 | 状态 |
|---|---|
| 26 键 QWERTY 拼音布局、中文/英文/数字/符号/Emoji 页面 | 代码已实现，UI 待 Xcode 编译与真机验证 |
| 中文全拼、简拼、模糊拼音（z/zh、c/ch、s/sh、n/l、f/h 等） | 已实现并有单元测试 |
| `nihaobeijing` 类连续拼音切分、多切分排序、整句词级组合 | 已实现，核心检查通过 |
| 中文词语、单字、短语和部分互联网词汇 | 内置词库 123,581 条中文词条、464,188 条英中释义 |
| 中→英释义第二行、英→中本地查询 | 已实现；词典与候选栏绑定 |
| 本地用户词频与最近使用 | 已实现，App Group 本地 JSON |
| 二元/三元语言模型 | 已实现二进制 mmap 查询；内置 20,000 bigram + 20,000 trigram |
| Core ML 微型候选排序 | 已训练 `micro-linear-1`（9 维数值特征，CPU，1.4 KB） |
| 候选栏两行、横向滚动、深色模式 | 代码已实现，待视觉/触感真机验收 |
| 按键音、触感反馈 | 代码已实现，受设置控制 |
| 主 App 自动/手动更新、Ed25519 校验、原子安装、回滚 | 已实现并有安装/回滚测试 |
| 键盘扩展不依赖在线服务 | 架构上扩展只链接 `PrivateKeyboardCore`，不链接更新模块；隐私脚本检查 |
| 清除个人词频 | 已实现 |

未包含：语音输入、语音识别、在线输入法 API、广告/统计 SDK、第三方私有词库或接口。

## 快速开始

### 环境

- macOS + **Xcode 16 或更高**（iOS 17 SDK）
- Swift 6.1 工具链可用
- 可选：`xcodegen`（工程文件已生成；修改 `project.yml` 后可用它重新生成）

### 1. 构建核心并运行端到端检查

```bash
swift build
swift run core-check Resources/Generated
./scripts/check_privacy.sh
./scripts/typecheck_catalyst.sh
./scripts/smoke_keyboard_catalyst.sh
```

`core-check` 会实际打开内置二进制词库、执行连续拼音切分、候选生成、Core ML 推理、用户词频、签名 manifest 安装与回滚，并打印 Top-1/Top-3/Top-5 与延迟指标。

`typecheck_catalyst.sh` 使用 macOS SDK 内置的 Mac Catalyst UIKit/SwiftUI 对 App 和键盘扩展做类型检查；`smoke_keyboard_catalyst.sh` 进一步在 Catalyst 下实例化键盘视图并检查字母/数字/Emoji 页面与候选控件布局。它们不能替代 iOS SDK 构建，但能在没有 Xcode 时捕获 UIKit/SwiftUI API、类型和视图构建错误。

### 2. 用 Xcode 构建 App

```bash
open PrivateKeyboard.xcodeproj
```

在 Xcode 中：

1. 为 Host App 和 Keyboard Extension 选择同一个 Team；
2. 把 `project.yml`、`SharedSupport.swift`、两个 entitlements 中的
   `com.privatekeyboard.app` / `group.com.privatekeyboard.app` 改成你自己的唯一标识；
3. 确认两个 target 都启用 App Groups capability；
4. 选择 iOS 17+ 真机或模拟器运行 Host App；
5. 到 **设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → PrivateKeyboard** 启用键盘。无需“允许完全访问”。

也可以在 CI/已安装 Xcode 的机器上执行：

```bash
xcodebuild -project PrivateKeyboard.xcodeproj \
  -scheme PrivateKeyboard \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

> 当前开发机只有 Command Line Tools，`swift test` 会报 `no such module 'XCTest'`。测试文件已通过类型检查，27 个测试方法也已用本地 XCTest 兼容 shim 执行通过；标准 `swift test` 仍需 Xcode。

## 架构

```text
按键
  → UIKit KeyboardViewController
  → 本地拼音切分 / 模糊音 / 简拼
  → 只读二进制词库（mmap）
  → 二元/三元语言模型（按上下文按需读取）
  → Core ML 微型排序（失败时回退到可解释加权排序）
  → 两行候选栏
  → 选择后写本地用户词频
```

```text
PrivateKeyboard/
├── App/                      SwiftUI 主 App、设置、更新 UI
├── KeyboardExtension/        UIKit 自定义键盘
├── SharedCore/
│   └── Sources/
│       ├── PrivateKeyboardCore/     拼音/词典/LM/排序/用户词频（扩展链接）
│       └── PrivateKeyboardUpdater/  manifest/签名/下载/安装（仅主 App 链接）
├── DictionaryBuilder/        TSV → 二进制词库
├── ModelBuilder/             Core ML 模型训练/导出
├── DataSources/              可复现的小型 seed 与来源说明
├── Resources/Generated/      App 内置的派生二进制数据与模型
├── Tests/                    XCTest + 可执行 core-check
├── docs/                     数据格式、指标、更新协议
├── scripts/                  数据导入、n-gram、隐私检查
├── .github/workflows/        CI 与数据发布
├── PRIVACY.md
├── THIRD_PARTY_LICENSES.md
└── LICENSE
```

### 为什么分 `Core` 和 `Updater`

键盘扩展只链接 `PrivateKeyboardCore`。`PrivateKeyboardUpdater` 包含 `URLSession`、CryptoKit 验签和安装逻辑，只被 Host App 和测试链接。这样可以从依赖图层面证明键盘扩展不具备网络更新能力，而不是只在运行时“约定不联网”。

## 本地数据

内置数据（`Resources/Generated/`）由以下公开来源构建，并保留署名和许可证：

- **CC-CEDICT**：中文词条、拼音、简繁和英文释义，CC BY-SA 4.0；
- **wordfreq 3.1.1**：中文 Zipf 频率派生数值，数据 CC BY-SA 4.0，代码 Apache-2.0；
- **Tatoeba 中文句子**：仅派生二元/三元计数，CC BY 2.0 FR；
- **jieba**：分词/回退词频工具，MIT；
- **reviewed additions**：项目人工复核的少量短语和互联网词汇。

详细来源、版本、SHA-256、修改说明见 [DataSources/SOURCES.md](DataSources/SOURCES.md) 和 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。

词库是**项目自己的二进制派生数据库**，不是把第三方原始词库直接改名为本项目数据发布。原始语料不进入仓库或 release 资产。

### 数据规模（当前内置版本 `2026.11.1`）

- 中文词条：123,581
- 英中释义记录：464,188
- 拼音音节：467
- bigram：20,000（Tatoeba 派生）
- trigram：20,000
- Core ML 模型：9 个数值输入，1 个 `score` 输出

### 重新构建数据

```bash
swift run dictionary-builder \
  --source DataSources/seed \
  --out Resources/Generated \
  --data-version 2026.11.1

python3 ModelBuilder/build_model.py \
  --out Resources/Generated/candidate_scorer.mlmodel \
  --metadata Resources/Generated/candidate_scorer.model.json
```

发布用完整数据：

```bash
python3 scripts/import_cc_cedict.py \
  --cedict /path/to/cedict_1_0_ts_utf-8_mdbg.txt.gz \
  --wordfreq \
  --manual DataSources/manual_additions.tsv \
  --ngram DataSources/seed/ngram.tsv \
  --out /tmp/pk-source

swift run -c release dictionary-builder \
  --source /tmp/pk-source \
  --out /tmp/pk-dist \
  --data-version YOUR_VERSION \
  --source-name 'CC-CEDICT + wordfreq + Tatoeba + reviewed additions'
```

## 候选排序

可解释的 `WeightedPredictionScorer` 使用：

```text
基础词频 + 用户词频 + 最近使用 + 二元 LM + 三元 LM + 拼音匹配 + 释义可用性
```

`PredictionScorer` 是协议；`HybridPredictionScorer` 在模型可用时叠加 `CoreMLCandidateScorer`，模型缺失或推理失败时仍返回可解释分数。候选详情会附带每个分量的拆解（`ScoreBreakdown`），便于测试和调试。

Core ML 模型输入为：

`baseFrequency, userFrequency, recency, bigram, trigram, pinyinMatch, translationAvailability, candidateLength, contextLength`

模型只在本机 CPU 推理，不含用户数据；模型文件带版本和 SHA-256，跟随数据集版本原子更新，可回滚。

## 自动词库更新

`manifest.json` 包含：数据版本、最低 App 版本、最低 iOS、文件名、下载 URL、大小、SHA-256、Ed25519 签名、来源、许可证、构建时间。

主 App 流程：

1. HTTPS 获取 manifest；
2. 校验 schema/版本/URL；
3. 用内置公钥 Ed25519 验签；
4. 逐个下载文件；
5. 校验大小；
6. 校验 SHA-256；
7. 写入 staging；
8. 再次校验；
9. 原子切换 `current.json`；
10. 保留旧版本用于回滚；
11. 键盘扩展下次启动读取新版本。

失败不会改动旧版本。键盘扩展从不下载数据。

启用更新：

1. `swift run manifest-tool keygen Tools/secrets/private.txt Resources/UpdatePublicKey.txt`
2. 把私钥放到 GitHub Actions secret `ED25519_PRIVATE_KEY`；不要提交私钥；
3. 在 `App/Info.plist` 的 `PBManifestURL` 填入公开 manifest 地址；
4. 运行 `.github/workflows/data-release.yml`。

仓库当前附带的是**开发公钥**和示例 manifest；发布前必须替换为自己的密钥。`Tools/secrets/` 已被 `.gitignore` 忽略。

## 测试与指标

```bash
swift run core-check Resources/Generated
```

当前本地验证结果（2026-11-03）：

- 27 个 XCTest 测试方法：**27/27 通过**（通过 XCTest 兼容 shim 执行；标准 `swift test` 仍需 Xcode）
- Host App 与 Keyboard Extension：**Catalyst 类型检查通过**（不是 iOS SDK 构建）
- 键盘视图：Catalyst 下构建并布局通过（26 键字母页、数字页、Emoji 页、候选栏、深色模式颜色解析、按键/候选回调）
- 92 条中文金标准：Top-1 **100%**，Top-3 **100%**，Top-5 **100%**
- 候选平均延迟 **5.69 ms**，p95 **10.78 ms**（macOS Release；真机待测）
- Core ML：`Core ML micro-linear-1 · f1ec5f0b46`
- 词库：123,581 词条，464,188 英文释义
- 中英词典前缀查询：10/10
- manifest 签名/安装/回滚：通过

这不是“大厂级”指标，样本也只有 92 条。完整目标、未测项和验收门槛见 [docs/METRICS.md](docs/METRICS.md)。

## 隐私

- 不上传按键、正在输入的文本、上下文、个人词频；
- 不接入广告、统计或崩溃上报 SDK；
- 键盘扩展不链接 Updater/网络模块；
- 用户词频只保存在 App Group；
- 设置中可清除；
- 无需“允许完全访问”；
- 更新只由主 App 发起，且只下载公开词库/模型/许可证，不包含用户数据。

详见 [PRIVACY.md](PRIVACY.md)。

## 已知限制

- **UIKit/SwiftUI target 已通过 Catalyst 类型检查，但尚未用 iOS SDK/Xcode 构建，也未真机验证。**
- 没有大厂级数据、句子语料或模型；LM 只有 20k/20k n-gram，不能称为完整语言模型。
- 候选栏第二行可能截断长释义；简繁转换尚无 UI 切换（词库同时保存简繁）。
- 拼音直接写入文本域后再回删上屏，长文本/光标移动场景需要真机验证；当前没有使用 marked text。
- 自动更新需要配置真实公钥、私有签名 secret 和公开 manifest URL；仓库默认未启用网络更新。
- 启动画面为空 `UILaunchScreen`；无品牌启动画面。
- 未做真机内存、启动时间、电量、长时间稳定性测试。
- 尚未实现用户自定义词库、领域词库、拼音纠错、增量更新、句子级联想、崩溃恢复。

## 版本计划

**v1（当前工程目标）**：上述混合预测、完整内置数据、更新与回滚、隐私闭环。先通过 Xcode/CI 和真机验证，再谈日常使用。

**v2（长期日常使用）**：扩大互联网词汇覆盖、句子级联想、纠错、简繁转换、自定义/领域词库、增量更新、模型回滚、内存/启动/电量优化、键盘崩溃恢复、长期稳定性。

## 许可证

- 代码：Apache License 2.0（见 [LICENSE](LICENSE)）。
- 派生词库/模型数据：按各自来源许可证，主要是 CC BY-SA 4.0 与 CC BY 2.0 FR；见 [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)。
- 代码许可证不覆盖 `Resources/Generated/` 中的第三方派生数据。
