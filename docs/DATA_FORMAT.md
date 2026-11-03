# 二进制数据格式

所有整数为 little-endian。文件通过 `Data(contentsOf:options:.mappedIfSafe)` 映射，候选查询只读取命中的索引/记录，不将完整词库解码为对象数组。

## 通用约定

- 文件前缀为 8 字节 ASCII magic；
- 偏移 8 为 `UInt32` 格式版本；
- 所有字符串位于文件尾部字符串池，以 `\0` 结尾，UTF-8；
- 表内偏移为相对文件或相对字符串池的 `UInt32`/`UInt64`；
- 单个文件上限 512 MiB（运行时读取器检查）。

## `pinyin.bin`

| 偏移 | 类型 | 含义 |
|---:|---|---|
| 0 | 8 bytes | `PKPINY01` |
| 8 | UInt32 | 版本 1 |
| 12 | UInt32 | 音节数 |
| 16 | UInt64 | 记录表偏移（40） |
| 24 | UInt64 | 字符串池偏移 |
| 32 | UInt64 | 字符串池长度 |

记录 8 字节：`UInt32 stringOffset, UInt32 frequency`。音节用于切分合法性和频率加权。

## `dictionary.zh-en.bin`

Header 80 字节：

| 偏移 | 类型 | 含义 |
|---:|---|---|
| 0 | 8 | `PKDICT01` |
| 8 | UInt32 | 版本 1 |
| 12 | UInt32 | 词条数 |
| 16 | UInt32 | 全拼索引记录数 |
| 20 | UInt32 | 简拼索引记录数 |
| 24 | UInt32 | 释义记录数 |
| 28 | UInt32 | 最大词频（0 表示旧文件需回退扫描） |
| 32 | UInt64 | 词条表偏移 |
| 40 | UInt64 | 全拼索引偏移 |
| 48 | UInt64 | 简拼索引偏移 |
| 56 | UInt64 | 释义表偏移 |
| 64 | UInt64 | 字符串池偏移 |
| 72 | UInt64 | 字符串池长度 |

词条 32 字节：`frequency UInt32, flags UInt16, glossCount UInt16, simplifiedOffset, traditionalOffset, pinyinDisplayOffset, fullKeyOffset, abbreviationOffset, glossStart UInt32`。

索引记录 8 字节：`keyStringOffset UInt32, entryID UInt32`。索引按 `key` 升序，同 key 按 `frequency` 降序。这样 `nh` 这类大量同简拼的结果不会先返回罕见词。

释义 8 字节：`posStringOffset, definitionStringOffset`。

词条顺序即 ID。全拼键形如 `ni hao`，简拼为 `nh`。

## `dictionary.en-zh.bin`

Header 64 字节：magic `PKENZH01`、版本、记录数、索引数、记录表偏移、索引偏移、字符串池偏移、字符串池长度、保留 8 字节。

记录 16 字节：`normalizedEnglishOffset, posOffset, chineseOffset, definitionOffset`。

索引 8 字节：`keyOffset, recordID`；同 key 按构建时的词频降序。

## 语言模型

### `lm.bigram.bin`

Header 40 字节：`PKLMBI01`、版本、记录数、记录大小 24、flags、数据偏移 40、保留。

记录 24 字节：

```text
UInt64 contextHash
UInt64 tokenHash
Int32  logProbabilityX1000
UInt32 count
```

### `lm.trigram.bin`

magic `PKLMTRI1`，记录 32 字节：

```text
UInt64 firstHash
UInt64 secondHash
UInt64 tokenHash
Int32  logProbabilityX1000
UInt32 count
```

Hash 为 FNV-1a 64。模型按 `(context, token)` 排序，查询用二分查找定位上下文，只读取当前上下文附近的记录。FNV 碰撞最坏只会混合两个上下文分数，不会改变用户文本或词条 ID。

## `candidate_scorer.mlmodel`

Core ML 模型，9 个 `Double` 输入：

```text
baseFrequency, userFrequency, recency, bigram, trigram,
pinyinMatch, translationAvailability, candidateLength, contextLength
```

输出 `score: Double`，运行时裁剪到 0...1。模型元数据写入 `candidate_scorer.model.json`（版本、SHA-256、训练说明、R²）。

## App Group 布局

```text
<AppGroup>/PrivateKeyboardDatasets/
├── current.json
└── datasets/
    └── v-<dataVersion>-<uuid>/
        ├── pinyin.bin
        ├── dictionary.zh-en.bin
        ├── dictionary.en-zh.bin
        ├── lm.bigram.bin
        ├── lm.trigram.bin
        └── candidate_scorer.mlmodel
```

`current.json` 保存 current/previous 两个 `InstalledRelease`，写入使用原子替换。键盘扩展读取 current；失败时回退到扩展内置数据。`DatasetResolver` 只读取状态和文件，不包含安装器/网络代码。

## 为什么不直接用 JSON

- 词库约 30 MB，JSON 解码会产生大量堆对象；
- 键盘扩展内存预算紧张；
- 前缀/精确查询需要排序索引；
- 二进制 mmap 可以按页加载，避免一次解码全量数据。

用户词频是相反的情况：它很小、需要原子写、需要跨进程共享，因此用 App Group 中的 JSON。
