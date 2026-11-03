# 词库/模型更新协议

## 目标

- 主 App 是唯一可以下载数据的进程；
- 键盘扩展始终可以离线输入；
- 更新失败时保留旧版本；
- 服务端被攻破也不能让设备安装未签名的数据；
- 模型与词库一起版本化、可回滚。

## manifest 结构

示例见 `docs/manifest.example.json`。字段：

```json
{
  "schemaVersion": 1,
  "dataVersion": "2026.11.1",
  "minAppVersion": "1.0.0",
  "minOSVersion": "17.0",
  "builtAt": "2026-11-03T05:55:24Z",
  "source": {
    "name": "CC-CEDICT + wordfreq + Tatoeba + reviewed additions",
    "url": "https://www.mdbg.net/chinese/dictionary?page=cc-cedict",
    "license": "CC BY-SA 4.0 / CC BY 2.0 FR / MIT",
    "attribution": "CC-CEDICT by MDBG; wordfreq by Robyn Speer; Tatoeba contributors; jieba by fxsjy",
    "notes": "..."
  },
  "files": [
    {
      "name": "dictionary.zh-en.bin",
      "kind": "zh-en",
      "url": "https://github.com/ORG/REPO/releases/download/data-2026.11.1/dictionary.zh-en.bin",
      "size": 14577416,
      "sha256": "…64 hex…",
      "compression": "none",
      "modelVersion": ""
    }
  ],
  "signature": "base64 Ed25519 signature"
}
```

必须包含 `pinyin.bin`、`dictionary.zh-en.bin`、`dictionary.en-zh.bin`、`lm.bigram.bin`、`lm.trigram.bin`。模型 `candidate_scorer.mlmodel` 可选；没有模型时键盘自动回退到可解释加权排序。

## 签名

签名覆盖 **除 `signature` 字段外的完整 manifest**，按 `JSONEncoder` 的 `.sortedKeys` + `.withoutEscapingSlashes` 规范化后做 Ed25519。

- 公钥：`Resources/UpdatePublicKey.txt`，随 Host App 分发；
- 私钥：只在 GitHub Actions secret `ED25519_PRIVATE_KEY`，不要提交；
- 生成：

```bash
swift run manifest-tool keygen Tools/secrets/private.txt Resources/UpdatePublicKey.txt
```

- 校验：

```bash
swift run manifest-tool verify docs/manifest.example.json Resources/UpdatePublicKey.txt
```

发布工作流会在构建前验证 secret 对应的公钥与仓库公钥一致，不一致就拒绝发布。

## 安装流程

`UpdateService`（仅 Host App）：

1. HTTPS GET manifest（限制 2 MiB）；
2. JSON 解码；
3. 结构校验（文件白名单、大小、SHA-256 格式）；
4. Ed25519 验签；
5. 比较版本、`minAppVersion`、`minOSVersion`；
6. 逐个 HTTPS 下载文件到临时目录；
7. 校验大小；
8. 校验 SHA-256；
9. `DatasetInstaller` 复制到 `datasets/staging-*`；
10. 对 staging 再校验一次；
11. move 到最终版本目录；
12. 原子写 `current.json`，保留 previous；
13. 键盘扩展下次启动解析新 current。

失败在任何一步都会删除 staging/新版本目录，不改变 `current.json`。

## 回滚

主 App 的 “回滚到上一版本” 调用 `DatasetInstaller.rollback()`，交换 current/previous 指针。旧版本目录在安装新版本时不会被删除。`DatasetResolver` 验证文件存在后才使用，否则回退到 extension bundle。

## 密钥轮换

1. 生成新密钥对；
2. 用新公钥更新 `Resources/UpdatePublicKey.txt`；
3. 发布一个新 App 版本（旧 App 只信旧公钥）；
4. 在 GitHub secret 中替换私钥；
5. 旧公钥签名的 manifest 在旧 App 上继续有效；
6. 不要试图用同一 `dataVersion` 重签不同文件。

## 威胁模型

| 威胁 | 防护 |
|---|---|
| 恶意 Wi-Fi/中间人篡改词库 | HTTPS + SHA-256 + Ed25519 |
| 服务端替换 manifest | Ed25519 公钥固定在内置 App |
| 旧版本降级攻击 | 版本比较；客户端可拒绝旧数据 |
| 更新中断/崩溃 | staging + 原子指针 + 旧版本保留 |
| 键盘扩展偷偷联网 | 扩展 target 不链接 Updater/网络模块；CI 符号检查 |
| 用户词频泄露 | 仅 App Group，本地文件；无网络代码路径 |
| 伪造发布资产 | 发布工作流校验 secret 公钥与内置公钥一致 |

## GitHub Actions

`.github/workflows/data-release.yml`：

- 每周一/手动；
- 下载 CC-CEDICT、Tatoeba、jieba；
- 比较最新 release 的 `SOURCE.json` 哈希，上游未变则跳过；
- 用 wordfreq 频率、人工覆盖、Tatoeba n-gram 构建；
- 训练并导出 Core ML 模型；
- 校验公钥匹配；
- 生成并签名 manifest；
- 创建 GitHub Release，上传派生二进制、manifest、模型、许可证、署名，不上传原始语料。

首次启用前必须配置 `ED25519_PRIVATE_KEY`，并把 `App/Info.plist` 的 `PBManifestURL` 设置为公开 manifest 地址（通常为 `https://github.com/ORG/REPO/releases/latest/download/manifest.json`）。

## 已知限制

- 当前仓库内置的是开发公钥，示例 manifest 不可用于生产。
- 没有实现增量差分更新；当前下载完整文件。
- 仅保留 current/previous 两级回滚状态。
- 更新失败场景有单元测试，但尚未做真机断电/磁盘满测试。
