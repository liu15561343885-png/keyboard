# 第三方数据与许可证

本项目代码使用 Apache License 2.0。`Resources/Generated/` 中的词库、语言模型和派生数据**不适用**代码许可证，而适用下列来源许可证。发布时必须同时附带本文件和对应许可证文本。

## CC-CEDICT

- 来源：https://www.mdbg.net/chinese/dictionary?page=cc-cedict
- 上游项目：CC-CEDICT，社区维护，由 MDBG 发布
- 许可证：Creative Commons Attribution-ShareAlike 4.0 International（CC BY-SA 4.0）
- 许可证全文：[licenses/CC-BY-SA-4.0.txt](licenses/CC-BY-SA-4.0.txt)
- 本项目使用：中文词条、简体/繁体、拼音、英文释义
- 修改：
  - 去除声调数字并规范化为 ASCII 拼音键；
  - 将多行词条拆分为 `words.tsv` / `translations.tsv`；
  - 附加 POS 启发式标签（非 CC-CEDICT 原始字段）；
  - 合并 wordfreq 频率；
  - 构建为带索引的 mmap 二进制词典；
  - 人工复核的短语覆盖见 `DataSources/manual_additions.tsv`。

CC-CEDICT 的 ShareAlike 义务适用于派生词典二进制。发布时保留来源、版本、修改说明和许可证。

## wordfreq

- 来源：https://github.com/rspeer/wordfreq
- 版本：3.1.1
- 作者：Robyn Speer 及贡献者
- 代码许可证：Apache License 2.0（见 [licenses/Apache-2.0-wordfreq.txt](licenses/Apache-2.0-wordfreq.txt)）
- 数据许可证：CC BY-SA 4.0
- 本项目使用：中文词频的派生数值，用于候选基础排序；不发布 wordfreq 原始词表或语料文本。
- 上游数据来源说明（wordfreq README）：Wikipedia、OPUS OpenSubtitles、SUBTLEX-CH、Google Books Ngrams、OSCAR、Twitter、Reddit、Jieba 等。完整来源列表和署名要求见上游 README 的 “Sources and supported languages” 与 “License” 小节。
- 附加署名：SUBTLEX 作者 Marc Brysbaert 等；OpenSubtitles；Wikipedia 贡献者；Tatoeba（如适用）。

## Tatoeba 中文句子（n-gram 派生）

- 来源：https://tatoeba.org/
- 下载：https://downloads.tatoeba.org/exports/per_language/cmn/cmn_sentences.tsv.bz2
- 许可证：Creative Commons Attribution 2.0 France（CC BY 2.0 FR），除非个别句子标注 CC0
- 许可证链接：https://creativecommons.org/licenses/by/2.0/fr/
- 本项目使用：仅聚合 bigram/trigram 计数，不发布句子原文。
- 修改：jieba 分词、去除标点/数字、计数、取高频 n-gram，构建为二进制 LM。

## jieba

- 来源：https://github.com/fxsjy/jieba
- 许可证：MIT（见 [licenses/MIT-jieba.txt](licenses/MIT-jieba.txt)）
- 本项目使用：构建时中文分词和可选词频；不修改 jieba 源码，不把 jieba 作为运行时依赖。

## 构建工具（不随 App 分发）

- scikit-learn 1.5.1：BSD-3-Clause，仅用于本地训练微型线性模型；
- coremltools 8.3.0：BSD-3-Clause，仅用于导出 `.mlmodel`；
- Python、NumPy 等构建依赖按其各自许可证使用。

这些工具不进入 iOS App，不接收用户数据。

## 明确排除

本项目不包含、不复制、不逆向搜狗、百度、腾讯、微软或其他输入法的私有词库、私有接口、私有模型或用户数据。候选数据仅来自上述公开许可证来源与项目人工复核条目。

## 发布检查清单

- [ ] 附带本文件和 `licenses/` 全文；
- [ ] manifest 的 `source.name`、`source.url`、`source.license`、`source.attribution` 完整；
- [ ] release notes 写明上游版本/SHA-256、修改说明、构建时间；
- [ ] 不把 CC-CEDICT/wordfreq/Tatoeba 原始语料作为本项目自有数据发布；
- [ ] 保留 CC BY-SA 的相同方式共享义务；
- [ ] 保留 Tatoeba 和 wordfreq 的署名。
