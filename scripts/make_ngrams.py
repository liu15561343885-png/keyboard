#!/usr/bin/env python3
"""Derive bigram/trigram counts from Tatoeba Chinese sentences.

Tatoeba sentences are CC BY 2.0 FR (some CC0); the raw corpus is not
committed. Only aggregate n-gram counts are emitted, with attribution in
DataSources/SOURCES.md and THIRD_PARTY_LICENSES.md.
"""
from __future__ import annotations

import argparse
import bz2
import re
from collections import Counter
from pathlib import Path

import jieba

HAN = re.compile(r"^[\u3400-\u9fff]{1,6}$")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--sentences", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--limit", type=int, default=5000)
    parser.add_argument("--manual", default=None)
    args = parser.parse_args()

    bigrams: Counter[tuple[str, str]] = Counter()
    trigrams: Counter[tuple[str, str, str]] = Counter()
    opener = bz2.open if args.sentences.endswith(".bz2") else open
    with opener(args.sentences, "rt", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t", 2)
            if len(parts) != 3:
                continue
            text = parts[2].strip()
            if not text:
                continue
            tokens = [t for t in jieba.lcut(text) if HAN.match(t)]
            for index in range(len(tokens) - 1):
                bigrams[(tokens[index], tokens[index + 1])] += 1
            for index in range(len(tokens) - 2):
                trigrams[(tokens[index], tokens[index + 1], tokens[index + 2])] += 1

    manual_bigrams: Counter[tuple[str, str]] = Counter()
    manual_trigrams: Counter[tuple[str, str, str]] = Counter()
    if args.manual and Path(args.manual).exists():
        for line in Path(args.manual).read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if parts[0] == "bi" and len(parts) >= 4:
                try:
                    manual_bigrams[(parts[1], parts[2])] += int(parts[3])
                except ValueError:
                    pass
            elif parts[0] == "tri" and len(parts) >= 5:
                try:
                    manual_trigrams[(parts[1], parts[2], parts[3])] += int(parts[4])
                except ValueError:
                    pass
    bigrams.update(manual_bigrams)
    trigrams.update(manual_trigrams)

    with open(args.out, "w", encoding="utf-8") as handle:
        handle.write("# type\tcontext\tsecond\ttoken\tcount\n")
        handle.write("# Derived from Tatoeba Chinese sentences; see DataSources/SOURCES.md.\n")
        for (first, second), count in bigrams.most_common(args.limit):
            if count < 2:
                continue
            handle.write(f"bi\t{first}\t{second}\t{count}\n")
        for (first, second, third), count in trigrams.most_common(args.limit):
            if count < 2:
                continue
            handle.write(f"tri\t{first}\t{second}\t{third}\t{count}\n")
    print(f"bigrams={len(bigrams)} trigrams={len(trigrams)} emitted<= {args.limit} each")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
