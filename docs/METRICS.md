# 指标与验收记录

> **结论先行：当前只能证明核心库在 macOS 上可运行，不能证明“可日常使用”。**
>
> UIKit/SwiftUI 代码已通过 Mac Catalyst SDK 类型检查，39 个 XCTest 测试方法已在本机 Xcode 16.4 `swift test` 和 iPhone 16 Simulator `xcodebuild test` 中执行通过；但 iOS SDK 构建、真机启动、键盘扩展峰值内存、长期稳定性仍未验证。未测项不会用“应该”填成通过。

## 测量环境

| 项 | 值 |
|---|---|
| 设备 | Intel Core i7-12700H，32 GB |
| 系统 | macOS 15.6 (24G84) |
| Swift | 6.1.2 (swiftlang-6.1.2.1.2) |
| 构建 | `swift run -c release core-check Resources/Generated` |
| 数据 | 内置 `2026.11.1`：123,586 词条、464,222 英中释义、467 音节、20,000 bigram、20,000 trigram |
| 模型 | Core ML `micro-linear-1`，CPU，9 维输入 |
| 日期 | 2026-11-03 |

这是桌面 CPU 的 Release 结果，**不是 iPhone 键盘扩展测量**。

## 已测结果

| 指标 | 结果 | 样本/说明 |
|---|---:|---|
| 中文拼音 Top-1 命中率 | **100%** | 98 条人工金标准，见 `Tests/CoreCheck/main.swift` |
| 中文 Top-3 命中率 | **100%** | 同上 |
| 中文 Top-5 命中率 | **100%** | 同上 |
| 中英词典前缀命中率 | **100%** | 10 条英文查询各取至少 1 条 |
| 候选平均延迟 | **6.46 ms** | 98 次串行查询，Release，macOS；多次运行约 6.0–6.7 ms |
| 候选中位延迟 | **5.35 ms** | 同上 |
| 候选 p95 延迟 | **11.46 ms** | 同上 |
| 候选最大延迟 | **38.44 ms** | 同上 |
| 连续拼音组合 | 通过 | `nihaobeijing` → `你好北京` |
| 模糊拼音 | 通过 | `zongguo` + zh/z → `中国` |
| 简拼 | 通过 | `nh` → 含 `你好` |
| 用户词频提升 | 通过 | 记录 `我比你` 后进入候选 |
| 简繁显示切换 | 通过 | 同一拼音 `ai` 简体输出 `爱`，繁体输出 `愛` |
| 自定义词库 | 通过 | 全拼/简拼命中、持久化、重复/非法输入拒绝、备份排除 |
| Ed25519 manifest | 通过 | 签名、篡改拒绝 |
| 更新传输/HTTPS 检查 | 通过 | `UpdateService` URLProtocol 测试：manifest 下载、非 HTTPS 拒绝 |
| 安装/回滚 | 通过 | 两次安装 + rollback 测试 |
| 更新失败原子性 | 通过 | 失败安装不改变 current 版本 |
| 模型文件更新/回滚 | 通过 | 模型版本写入 current，回滚后恢复 |
| manifest 路径穿越 | 通过 | `../pinyin.bin` 被拒绝 |
| 键盘扩展网络 API | 源码级检查通过 | `scripts/check_privacy.sh` |
| Apple 隐私清单 | 通过 | `PrivacyInfo.xcprivacy` 同时进入 App 与扩展；无追踪、无采集声明 |
| 本地数据备份排除 | 通过 | 用户词频文件与数据集根目录设置 `isExcludedFromBackup` |
| 数据/配置一致性 | 通过 | `scripts/check_artifacts.py`：哈希、版本、App Group、公钥、manifest 示例 |
| UIKit/SwiftUI 类型检查 | 通过 | `scripts/typecheck_catalyst.sh`，Mac Catalyst SDK，非 iOS SDK 构建 |
| Catalyst 产品链接 | 通过 | `scripts/build_catalyst_products.sh`：Host App 可执行文件 + Extension dylib |
| Extension API 限制 | 通过 | Extension 以 `-application-extension` 编译/链接 |
| 端到端键盘输入 | 通过（条件） | 预启用 PrivateKeyboard 后，坐标输入 `nihao → 你好`；日志 `docs/evidence/simulator-keyboard-ui-test.log`；未启用时 XCTSkip |
| 键盘 UI 测试执行 | 1/1 通过 | `PrivateKeyboardUITests`；独立 scheme，不进入 CI |
| 长按删除 | 通过 | 删除键存在 `UILongPressGestureRecognizer`，重复计时器实现连续删除 |
| 键盘视图构建/布局 | 通过 | `scripts/smoke_keyboard_catalyst.sh`：字母页 33 控件、数字页 31、24 个候选的横向滚动、候选栏 56 pt、深色模式颜色解析、按键/候选点击回调、KeyboardViewController 实例化（288 pt / 34 键） |
| XCTest 测试方法执行 | 39/39 通过 | 本机 `swift test`；本机 iPhone 16 Simulator `xcodebuild test`；CI 均通过 |
| iOS Simulator 构建 | 通过 | 本机 Xcode 16.4 / iPhone 16 / iOS 18.6；`xcodebuild build` 成功 |
| iOS Simulator 构建（CI） | 通过 | GitHub Actions Xcode 16.4；[run 41630721721](https://github.com/liu15561343885-png/keyboard/actions/runs/41601735713) |
| iOS Simulator 单元测试 | 通过 | 本机 `xcodebuild test` 39/39；CI 同一 run 通过 |
| Extension 符号检查 | 通过 | CI `nm` 检查无 URLSession |
| 断网逻辑可用性 | 未做设备断网测试 | 扩展不链接网络模块，但需真机验证 |

> 98 条查询仍是开发者自选，不能代表真实输入分布。Top-1 100% **不是**通用准确率。

## 未测项（必须补齐后才能讨论日常使用）

| 指标 | 目标 | 状态 |
|---|---|---|
| 500+ 条盲测中文拼音 Top-1 | ≥ 85% | 未测 |
| Top-3 | ≥ 95% | 未测 |
| 常用短语联想准确率 | ≥ 70% | 未测 |
| 中英双向词典盲测命中率 | ≥ 95% | 未测 |
| 引擎初始化/模型加载 | 7.29–19.76 ms（macOS 代理） | 真机键盘扩展未测 |
| T9 `64426` 候选延迟 | mean 19.05 ms / p95 30.55 ms | macOS Release；真机未测 |
| 首次候选推理 | 3.19 ms（macOS 代理） | 真机未测 |
| 键盘冷启动到可按键 | < 300 ms（iPhone 12 级） | 未测 |
| 候选 p95 响应 | < 50 ms（真机 Release） | 未测 |
| 键盘扩展峰值内存 | < 60 MB | 未测 |
| 30 分钟连续输入 | 0 崩溃、无持续增长 | 未测 |
| 飞行模式输入 | 100% 可用 | 未测 |
| 更新失败回滚 | 100% 保持旧版本 | 逻辑测试通过，未真机测 |
| 低内存设备（3 GB） | 不 jetsam | 未测 |
| 电量/CPU | 无基线 | 未测 |

## 性能风险

1. **候选路径**在 Debug 下曾达到 20 ms 均值；Release 降到 7 ms，但主线程仍可能被大候选集和 Core ML 首次加载拖慢。键盘扩展应在真机上测首键延迟。
2. **Core ML 编译**：若 Xcode 把 `.mlmodel` 编译为 `.mlmodelc` 并随包分发，可避免运行时编译；否则首次加载会调用 `MLModel.compileModel`。需要检查最终 App bundle。
3. **FNV-1a 64 冲突**：n-gram 只用 hash 排序，冲突最坏导致上下文分数混合，不会破坏文本；但应在真实数据上监控。
4. **拼音直接写入文本域**：当前方案在光标移动、撤销、外部文本变化时可能回删错误。真机验证前不建议称为稳定。
5. **iOS 真机未验证**：iOS Simulator 已通过 CI 构建/测试；仍需真机对 Asset Catalog、entitlements、扩展加载和稳定性做验证。

## 验收规则

只有以下全部成立，README 才可以把状态从 Alpha 改为“可日常使用”：

- CI 的 iOS Simulator build/test 全绿，真机 30 分钟稳定；
- 500+ 盲测集 Top-1 ≥ 85%，Top-3 ≥ 95%；
- 候选 p95 < 50 ms，冷启动 < 300 ms，峰值内存 < 60 MB；
- 飞行模式全功能输入；
- 更新失败/断电模拟后旧版本仍可用；
- 简繁、标点、中英混输、删除/空格/回车/下一键盘全部真机通过；
- 许可证与隐私文档随 release 发布。
