# 数据来源与构建记录

本目录保留可复现的源 TSV 和构建说明。发布数据由 `DictionaryBuilder` 生成；原始第三方语料不提交到仓库，也不作为本项目的原创数据发布。

## 当前内置版本 `2026.11.1`

构建时间：2026-11-03（UTC）

| 来源 | 版本/日期 | 用途 | 许可证 |
|---|---|---|---|
| CC-CEDICT（MDBG 导出） | 2026-11-03 下载；解压文本 SHA-256 `0c0d0ccea1f05eae5ffacefa37f911211455c0cfbab8cf0418b8c7a823d57b31` | 中文词条、简繁、拼音、英文释义 | CC BY-SA 4.0 |
| wordfreq | 3.1.1 | 中文频率派生数值 | 数据 CC BY-SA 4.0；代码 Apache-2.0 |
| Tatoeba 中文句子 | 89,248 行；bz2 SHA-256 `d603c1b9c67fb7a5a68c56fe6df5c935025ca1f36a1f9a912c33ed6dbed91743` | 仅派生 bigram/trigram 计数 | CC BY 2.0 FR（个别 CC0） |
| jieba | 0.42.1 | 分词/可选回退词频 | MIT |
| 人工复核条目 | 见 `manual_additions.tsv` | 示例短语、互联网词、POS 覆盖 | 项目 Apache-2.0 |

CC-CEDICT 下载文件（gzip）SHA-256：`e203bbf4a28c2ab54762e9b1fb813e53aa9112939704e71a5117f3b3555a46cb`。

> 下载地址：https://www.mdbg.net/chinese/dictionary?page=cc-cedict
>
> Tatoeba：https://downloads.tatoeba.org/exports/per_language/cmn/cmn_sentences.tsv.bz2
>
> wordfreq：https://github.com/rspeer/wordfreq
>
> jieba：https://github.com/fxsjy/jieba

## 修改说明

1. CC-CEDICT 拼音去掉声调数字、`u:` 规范为 `v`，转为 ASCII 音节键；
2. 词条按 `simplified + traditional + pinyinKey` 去重；
3. 英文释义取前两条，附 POS 启发式标签；
4. 使用 wordfreq 中文频率（概率 × 1e9 转为正整数排序权重）；
5. 人工覆盖 `我爱你/我比你/卧病/点赞/热搜/短视频/表情包/种草/打卡/输入法/词库/隐私/本地/离线/端到端` 等条目；
6. Tatoeba 句子用 jieba 分词，过滤非中文 token，统计 bigram/trigram，取最高频各 5,000 条；
7. 构建为 `pinyin.bin`、`dictionary.zh-en.bin`、`dictionary.en-zh.bin`、`lm.bigram.bin`、`lm.trigram.bin`；
8. 训练 9 维 Core ML 微型线性排序器 `candidate_scorer.mlmodel`；
9. 生成 SHA-256、manifest，并用 Ed25519 签名。

## 小型 seed

`DataSources/seed/` 是 297 条左右的可审查开发种子（142 条人工挑选词 + 单字），用于快速构建和测试。它不是发布用完整词典。完整数据由 `scripts/import_cc_cedict.py` 生成。

seed 中的 CC-CEDICT 派生字段同样受 CC BY-SA 4.0 约束。

## 构建命令

```bash
python3 scripts/import_cc_cedict.py \
  --cedict /path/to/cedict_1_0_ts_utf-8_mdbg.txt.gz \
  --wordfreq \
  --manual DataSources/manual_additions.tsv \
  --ngram DataSources/seed/ngram.tsv \
  --out /tmp/pk-source

python3 scripts/make_ngrams.py \
  --sentences /path/to/cmn_sentences.tsv.bz2 \
  --out /tmp/pk-source/ngram.tsv \
  --limit 20000 \
  --manual DataSources/ngram_manual.tsv

swift run -c release dictionary-builder \
  --source /tmp/pk-source \
  --out /tmp/pk-dist \
  --data-version 2026.11.1 \
  --source-name 'CC-CEDICT + wordfreq + Tatoeba + reviewed additions' \
  --source-url 'https://www.mdbg.net/chinese/dictionary?page=cc-cedict' \
  --license 'CC BY-SA 4.0 (CC-CEDICT, wordfreq); CC BY 2.0 FR (Tatoeba n-grams); MIT (jieba)' \
  --attribution 'CC-CEDICT by MDBG; frequency data derived from wordfreq by Robyn Speer; n-gram counts derived from Tatoeba contributors; jieba by fxsjy. See THIRD_PARTY_LICENSES.md.'

python3 ModelBuilder/build_model.py \
  --out /tmp/pk-dist/candidate_scorer.mlmodel \
  --metadata /tmp/pk-dist/candidate_scorer.model.json
```

## 发布约束

- 原始 CC-CEDICT/Tatoeba 文本不进入 release；
- release 只包含构建后的二进制、manifest、签名、来源说明和许可证；
- `Resources/Generated/dataset.json` 记录当前文件哈希、来源和构建时间；
- GitHub Actions 的 `data-release.yml` 在创建 release 前验证公钥与 secret 匹配，并拒绝覆盖旧版本。
