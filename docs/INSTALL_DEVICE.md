# 真机安装

当前工程已改为：

```text
App:        com.liu15561343885.privatekeyboard
Keyboard:   com.liu15561343885.privatekeyboard.keyboard
App Group:  group.com.liu15561343885.privatekeyboard
UI Tests:   com.liu15561343885.privatekeyboard.uitests
Unit Tests: com.liu15561343885.privatekeyboard.tests
```

`KeyboardExtension/Info.plist` 的 `RequestsOpenAccess` 已设为 `true`：键盘需要“允许完全访问”才能读取 App Group 中的共享词库、设置和用户词频。扩展仍然没有网络代码。

## 唯一需要你做的签名步骤

本机当前没有任何 Apple Development 证书，也没有 Xcode 登录账号，因此无法替你生成签名。

1. Xcode → Settings → Accounts → 添加 Apple ID。
2. 打开 `PrivateKeyboard.xcodeproj`。
3. 选中 `PrivateKeyboard` target → Signing & Capabilities：
   - Team 选择你的账号；
   - 确认 App Groups 中存在 `group.com.liu15561343885.privatekeyboard`。
4. 选中 `PrivateKeyboardKeyboard` target，重复选择同一个 Team 和 App Group。
5. iPhone 连接 Mac，开启开发者模式并信任电脑。
6. Xcode 顶部选择你的 iPhone，Run。
7. 如果提示 Untrusted Developer：设置 → 通用 → VPN 与设备管理 → 信任。
8. iPhone：设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → PrivateKeyboard。
9. 点开 PrivateKeyboard，打开“允许完全访问”。

## 验证

- Host App 的“键盘测试”输入框：`nihao → 你好`。
- 光标放在已有文字中间再输入，确认没有错删。
- 连续输入 30 分钟，观察崩溃和内存。
- 回到 Host App 查看“个人词条”是否增加，确认 App Group 共享生效。

如果使用免费 Apple ID 无法启用 App Groups，需要改用付费 Apple Developer Program；这是 Apple 的签名限制，不是工程代码问题。
