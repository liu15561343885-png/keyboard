#!/usr/bin/env python3
"""Build the small, reviewable development seed used by unit tests.

This is NOT the release dictionary. Release data is generated from CC-CEDICT
(with attribution and share-alike licensing) by scripts/import_cc_cedict.py.
"""
import argparse
import gzip
import re
from datetime import date
from pathlib import Path

WORDS = [
    ("我", 950000), ("你", 850000), ("他", 700000), ("她", 500000),
    ("我们", 600000), ("你们", 300000), ("他们", 400000),
    ("你好", 200000), ("您好", 100000), ("爱", 300000), ("我爱你", 50000),
    ("喜欢", 250000), ("谢谢", 300000), ("再见", 200000),
    ("北京", 300000), ("中国", 500000), ("上海", 250000), ("广州", 150000),
    ("深圳", 180000), ("今天", 300000), ("明天", 200000), ("昨天", 150000),
    ("现在", 400000), ("时间", 350000), ("天气", 250000),
    ("很好", 200000), ("好的", 300000), ("不", 500000), ("是", 800000),
    ("有", 700000), ("没有", 500000), ("可以", 400000), ("请", 400000),
    ("请问", 150000), ("什么", 500000), ("怎么", 400000), ("为什么", 300000),
    ("哪里", 200000), ("这个", 400000), ("那个", 300000), ("一个", 400000),
    ("人", 500000), ("朋友", 300000), ("家", 300000), ("工作", 350000),
    ("学习", 300000), ("学校", 200000), ("学生", 250000), ("老师", 200000),
    ("手机", 300000), ("电脑", 250000), ("网络", 300000), ("输入法", 100000),
    ("键盘", 200000), ("中文", 250000), ("英文", 200000), ("翻译", 150000),
    ("词库", 30000), ("隐私", 80000), ("安全", 200000), ("本地", 100000),
    ("在线", 150000), ("更新", 150000), ("版本", 100000),
    ("对不起", 200000), ("没关系", 150000), ("吃饭", 200000), ("喝水", 100000),
    ("睡觉", 200000), ("起床", 150000), ("上班", 200000), ("下班", 180000),
    ("回家", 200000), ("看电影", 100000), ("听音乐", 80000), ("玩游戏", 100000),
    ("卧病", 20000), ("生病", 150000), ("医院", 150000), ("医生", 150000),
    ("药", 100000), ("帮助", 200000), ("需要", 300000), ("知道", 400000),
    ("觉得", 350000), ("认为", 300000), ("希望", 250000), ("开始", 300000),
    ("结束", 200000), ("已经", 400000), ("正在", 300000), ("可能", 350000),
    ("但是", 400000), ("因为", 400000), ("所以", 400000), ("如果", 300000),
    ("还是", 300000), ("或者", 200000), ("以及", 250000), ("而且", 200000),
    ("虽然", 200000), ("然后", 300000), ("最后", 250000), ("一起", 300000),
    ("一点", 250000), ("一下", 250000), ("非常", 300000), ("真的", 300000),
    ("很", 600000), ("太", 400000), ("更", 300000), ("最", 400000),
    ("能", 500000), ("会", 500000), ("要", 600000), ("想", 500000),
    ("去", 500000), ("来", 500000), ("看", 500000), ("听", 300000),
    ("说", 500000), ("读", 150000), ("写", 200000), ("买", 250000),
    ("卖", 150000), ("吃", 300000), ("喝", 200000), ("玩", 200000),
    ("点赞", 100000), ("网友", 80000), ("热搜", 50000), ("直播", 150000),
    ("短视频", 120000), ("表情包", 60000), ("流量", 150000), ("种草", 40000),
    ("打卡", 80000), ("我比你", 10000), ("北京欢迎你", 8000),
    ("你好吗", 60000), ("谢谢你", 90000), ("没问题", 70000),
]

MANUAL = {
    "我爱你": ("wo ai ni", "愛你", "phr.", "I love you"),
    "我比你": ("wo bi ni", "我比你", "phr.", "more ... than you"),
    "卧病": ("wo bing", "臥病", "v.", "be bedridden"),
    "北京欢迎你": ("bei jing huan ying ni", "北京歡迎你", "phr.", "Welcome to Beijing"),
    "输入法": ("shu ru fa", "輸入法", "n.", "input method"),
    "表情包": ("biao qing bao", "表情包", "n.", "reaction image; meme"),
    "短视频": ("duan shi pin", "短視頻", "n.", "short video"),
    "种草": ("zhong cao", "種草", "v.", "to recommend a product; lit. plant grass"),
    "热搜": ("re sou", "熱搜", "n.", "trending search"),
    "点赞": ("dian zan", "點讚", "v.", "to like (a post)"),
    "打卡": ("da ka", "打卡", "v.", "to check in; to clock in"),
    "您好": ("nin hao", "您好", "phr.", "hello (polite)"),
    "很好": ("hen hao", "很好", "adj.", "very good"),
    "好的": ("hao de", "好的", "phr.", "OK; all right"),
    "喝水": ("he shui", "喝水", "v.", "drink water"),
    "看电影": ("kan dian ying", "看電影", "v.", "watch a movie"),
    "听音乐": ("ting yin yue", "聽音樂", "v.", "listen to music"),
    "玩游戏": ("wan you xi", "玩遊戲", "v.", "play games"),
    "你好吗": ("ni hao ma", "你好嗎", "phr.", "how are you?"),
    "谢谢你": ("xie xie ni", "謝謝你", "phr.", "thank you"),
    "没问题": ("mei wen ti", "沒問題", "phr.", "no problem"),
}

POS_OVERRIDES = {
    "我": "pron.", "你": "pron.", "他": "pron.", "她": "pron.",
    "我们": "pron.", "你们": "pron.", "他们": "pron.",
    "不": "adv.", "很": "adv.", "太": "adv.", "更": "adv.", "最": "adv.",
    "非常": "adv.", "已经": "adv.", "正在": "adv.", "可能": "adv.",
    "但是": "conj.", "因为": "conj.", "所以": "conj.", "如果": "conj.",
    "还是": "conj.", "或者": "conj.", "以及": "conj.", "而且": "conj.",
    "虽然": "conj.", "然后": "adv.", "最后": "adv.",
    "北京": "n.", "中国": "n.", "上海": "n.", "广州": "n.", "深圳": "n.",
    "今天": "n.", "明天": "n.", "昨天": "n.", "现在": "n.", "时间": "n.",
    "天气": "n.", "朋友": "n.", "家": "n.", "工作": "n.", "学校": "n.",
    "学生": "n.", "老师": "n.", "手机": "n.", "电脑": "n.", "网络": "n.",
    "键盘": "n.", "中文": "n.", "英文": "n.", "翻译": "n.", "词库": "n.",
    "隐私": "n.", "版本": "n.", "医院": "n.", "医生": "n.", "药": "n.",
    "网友": "n.", "流量": "n.",
    "爱": "v.", "喜欢": "v.", "谢谢": "v.", "需要": "v.", "知道": "v.",
    "觉得": "v.", "认为": "v.", "希望": "v.", "开始": "v.", "结束": "v.",
    "帮助": "v.", "吃饭": "v.", "喝水": "v.", "睡觉": "v.", "起床": "v.",
    "上班": "v.", "下班": "v.", "回家": "v.", "看电影": "v.", "听音乐": "v.",
    "玩游戏": "v.", "生病": "v.", "能": "v.", "会": "v.", "要": "v.",
    "想": "v.", "去": "v.", "来": "v.", "看": "v.", "听": "v.",
    "说": "v.", "读": "v.", "写": "v.", "买": "v.", "卖": "v.",
    "吃": "v.", "喝": "v.", "玩": "v.",
    "很好": "adj.", "好的": "adj.", "安全": "adj.", "一起": "adv.",
    "一点": "adv.", "一下": "adv.", "真的": "adv.",
    "是": "v.", "有": "v.", "没有": "v.", "可以": "v.", "请": "v.",
    "请问": "v.", "什么": "pron.", "怎么": "adv.", "为什么": "adv.",
    "哪里": "pron.", "这个": "pron.", "那个": "pron.", "一个": "num.",
    "人": "n.", "对不起": "phr.", "没关系": "phr.", "再见": "phr.",
    "你好": "phr.", "谢谢": "phr.", "好的": "adj.", "我比你": "phr.",
}


def norm_pinyin(raw: str) -> str:
    value = raw.replace("u:", "v").replace("ü", "v").lower()
    value = re.sub(r"[0-9]", "", value)
    value = value.replace("'", " ").replace("·", " ")
    return " ".join(value.split())


def infer_pos(definition: str) -> str:
    d = definition.lower()
    if d.startswith("to ") or "; to " in d:
        return "v."
    if d.startswith("a ") or "adjective" in d:
        return "adj."
    if "adverb" in d:
        return "adv."
    return "n."


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cedict", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    cc = {}
    line_re = re.compile(r"^(\S+) (\S+) \[([^\]]+)\] /(.*)/$")
    opener = gzip.open if args.cedict.endswith(".gz") else open
    with opener(args.cedict, "rt", encoding="utf-8") as handle:
        for line in handle:
            m = line_re.match(line.strip())
            if not m:
                continue
            trad, simp, pinyin, gloss = m.groups()
            key = simp
            if key not in cc:
                cc[key] = []
            cc[key].append((trad, norm_pinyin(pinyin), gloss))

    words = []
    translations = []
    used_syllables = set()
    for word, frequency in WORDS:
        entry = None
        if word in MANUAL:
            pinyin, trad, pos, definition = MANUAL[word]
            entry = (trad, pinyin, definition)
            translations.append((word, pos, definition))
        else:
            candidates = cc.get(word)
            if candidates:
                trad, pinyin, gloss = candidates[0]
                definitions = [g.strip() for g in gloss.split("/") if g.strip()]
                definition = "; ".join(definitions[:2])[:180]
                pos = POS_OVERRIDES.get(word, infer_pos(definition))
                entry = (trad, pinyin, definition)
                translations.append((word, pos, definition))
        if entry is None:
            print(f"skip missing {word}")
            continue
        trad, pinyin, _ = entry
        words.append((word, trad, pinyin, frequency))
        used_syllables.update(pinyin.split())

    # Include the single characters that make up the selected words. This keeps
    # single-character candidates and phrase composition working in the seed.
    word_set = {row[0] for row in words}
    for word, _ in list(WORDS):
        for character in word:
            if character in word_set:
                continue
            candidates = cc.get(character)
            if not candidates:
                continue
            trad, pinyin, gloss = candidates[0]
            definitions = [g.strip() for g in gloss.split("/") if g.strip()]
            if not definitions:
                continue
            definition = "; ".join(definitions[:2])[:180]
            pos = infer_pos(definition)
            words.append((character, trad, pinyin, 20000))
            translations.append((character, pos, definition))
            word_set.add(character)
            used_syllables.update(pinyin.split())

    # Manual n-grams are intentionally small; the release pipeline can replace
    # them with a licensed corpus build. They are real counts over a reviewed
    # phrase list, not invented probabilities.
    ngrams = [
        ("bi", "今天", "天气", 42), ("bi", "天气", "很好", 35),
        ("bi", "我", "爱", 18), ("bi", "爱", "你", 22),
        ("bi", "我", "比", 12), ("bi", "比", "你", 9),
        ("bi", "请问", "你", 16), ("bi", "谢谢", "你", 28),
        ("bi", "北京", "欢迎", 20), ("bi", "欢迎", "你", 18),
        ("bi", "对不起", "我", 8), ("bi", "没", "关系", 14),
        ("bi", "我们", "一起", 21), ("bi", "一起", "去", 17),
        ("bi", "你", "好", 33), ("bi", "您", "好", 12),
        ("bi", "今天", "很", 19), ("bi", "很", "好", 26),
        ("tri", "今天", "天气", "很好", 22),
        ("tri", "我", "爱", "你", 18),
        ("tri", "我", "比", "你", 8),
        ("tri", "请问", "你", "好", 10),
        ("tri", "北京", "欢迎", "你", 12),
        ("tri", "我们", "一起", "去", 9),
        ("tri", "谢谢", "你", "的", 7),
    ]

    with open(out / "words.tsv", "w", encoding="utf-8") as f:
        f.write("# Development seed derived from CC-CEDICT and manual review.\n")
        f.write("# License: CC BY-SA 4.0 for CC-CEDICT-derived fields; see THIRD_PARTY_LICENSES.md.\n")
        f.write("simplified\ttraditional\tpinyin\tfrequency\n")
        for row in words:
            f.write("\t".join(map(str, row)) + "\n")

    with open(out / "translations.tsv", "w", encoding="utf-8") as f:
        f.write("# simplified\tpart_of_speech\tdefinition\tsource\n")
        for simplified, pos, definition in translations:
            f.write(f"{simplified}\t{pos}\t{definition}\tCC-CEDICT/seed\n")

    with open(out / "pinyin.tsv", "w", encoding="utf-8") as f:
        f.write("# syllable\tfrequency\n")
        for syllable in sorted(used_syllables):
            f.write(f"{syllable}\t1\n")

    ngram_path = out / "ngram.tsv"
    if not ngram_path.exists():
        with open(ngram_path, "w", encoding="utf-8") as f:
            f.write("# type\tcontext_or_first\tsecond_or_token\ttoken_or_count\tcount\n")
            for item in ngrams:
                f.write("\t".join(map(str, item)) + "\n")

    print(f"words={len(words)} translations={len(translations)} syllables={len(used_syllables)}")
    print(f"generated {date.today().isoformat()}")


if __name__ == "__main__":
    main()
