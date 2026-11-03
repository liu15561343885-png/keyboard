# Contributing

## Ground rules

- 不提交任何私有输入法词库、私有接口、抓取的用户数据或未经许可的语料。
- 新数据必须有来源、版本、许可证、修改说明和可复现构建命令。
- 任何新增网络行为都必须放在 Host App/Updater，不得链接进 Keyboard Extension。
- 用户词频、输入内容和上下文不得写入日志或离开 App Group。

## Development

```bash
swift build
swift run core-check Resources/Generated
./scripts/check_privacy.sh
swift test            # requires Xcode/XCTest
```

iOS 真机/模拟器：

```bash
xcodebuild -project PrivateKeyboard.xcodeproj \
  -scheme PrivateKeyboard \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  CODE_SIGNING_ALLOWED=NO test
```

## Data changes

- 修改 `DataSources/` 后重新构建 `Resources/Generated`，并更新 `DataSources/SOURCES.md` 的版本/SHA。
- 新的第三方来源必须先更新 `THIRD_PARTY_LICENSES.md` 和 `licenses/`。
- 更新数据需要新的 Ed25519 签名；不得用同一 dataVersion 重签不同内容。

## Pull requests

- 说明改动了哪些文件、实现内容、验证方式和剩余风险；
- 不声称超过实际测试数据的效果；
- UI 变更请附模拟器/真机截图；
- 性能相关 PR 请附 Release 构建的 p50/p95 和内存数据。
