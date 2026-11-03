#!/usr/bin/env python3
"""Convert CC-CEDICT (CC BY-SA 4.0) into PrivateKeyboard source TSVs.

Only derived, reviewable TSVs are produced. The upstream raw file is never
committed to this repository or published as a release asset.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import re
import sys
from pathlib import Path

LINE_RE = re.compile(r"^(\S+) (\S+) \[([^\]]+)\] /(.*)/$")


def norm_pinyin(raw: str) -> str:
    value = raw.replace("u:", "v").replace("ü", "v").lower()
    value = re.sub(r"[0-9]", "", value)
    value = value.replace("'", " ").replace("·", " ")
    parts = re.findall(r"[a-z]+", value)
    return " ".join(parts)


def pos_for(gloss: str) -> str:
    g = gloss.lower()
    if g.startswith("to ") or "; to " in g:
        return "v."
    if g.startswith("a ") or "adjective" in g:
        return "adj."
    if "adverb" in g:
        return "adv."
    if "surname" in g or "name of" in g:
        return "n."
    return "n."


def clean_text(value: str) -> str:
    return value.replace("\t", " ").replace("\n", " ").strip()


def load_jieba(path: Path | None) -> dict[str, int]:
    frequencies: dict[str, int] = {}
    if path is None or not path.exists():
        return frequencies
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split(" ")
            if len(parts) < 2:
                continue
            try:
                frequencies[parts[0]] = max(1, int(parts[1]))
            except ValueError:
                continue
    return frequencies


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cedict", required=True)
    parser.add_argument("--jieba", default=None)
    parser.add_argument("--wordfreq", action="store_true", help="Use CC BY-SA 4.0 wordfreq frequency data when available")
    parser.add_argument("--out", required=True)
    parser.add_argument("--ngram", default="DataSources/seed/ngram.tsv")
    parser.add_argument("--max-entries", type=int, default=0)
    parser.add_argument("--manual", default=None)
    args = parser.parse_args()

    output = Path(args.out)
    output.mkdir(parents=True, exist_ok=True)
    frequencies = load_jieba(Path(args.jieba)) if args.jieba else {}
    if args.wordfreq:
        try:
            from wordfreq import get_frequency_dict
            wf = get_frequency_dict("zh", "large")
            # Convert probability to a positive integer ranking weight. This is a
            # derived frequency field, not a redistribution of raw corpus text.
            for word, probability in wf.items():
                frequencies[word] = max(1, int(round(probability * 1_000_000_000)))
            print(f"wordfreq entries: {len(wf)}")
        except Exception as exc:
            print(f"wordfreq unavailable: {exc}", file=sys.stderr)

    raw_hash = hashlib.sha256()
    entries: dict[tuple[str, str, str], tuple[int, str, str]] = {}
    opener = gzip.open if args.cedict.endswith(".gz") else open
    with opener(args.cedict, "rb") as handle:
        for raw in handle:
            raw_hash.update(raw)
            line = raw.decode("utf-8", errors="replace").strip()
            match = LINE_RE.match(line)
            if not match:
                continue
            traditional, simplified, pinyin_raw, gloss_raw = match.groups()
            pinyin = norm_pinyin(pinyin_raw)
            if not pinyin:
                continue
            if any(not ("a" <= ch <= "z" or ch == " ") for ch in pinyin):
                continue
            identity = (simplified, traditional, pinyin)
            if identity in entries:
                continue
            definitions = [clean_text(x) for x in gloss_raw.split("/") if clean_text(x)]
            if not definitions:
                continue
            definition = "; ".join(definitions[:2])[:220]
            frequency = frequencies.get(simplified, 1)
            entries[identity] = (frequency, definition, pos_for(definition))
            if args.max_entries and len(entries) >= args.max_entries:
                break

    # Reviewed additions and overrides, including product-specific phrases such
    # as 我比你. Format: simplified<TAB>traditional<TAB>pinyin<TAB>pos<TAB>definition[<TAB>frequency].
    if args.manual:
        manual_path = Path(args.manual)
        if manual_path.exists():
            with manual_path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    parts = line.split("\t")
                    if len(parts) < 5:
                        continue
                    simplified, traditional, pinyin, pos, definition = parts[:5]
                    manual_frequency = None
                    if len(parts) >= 6:
                        try:
                            manual_frequency = max(1, int(parts[5]))
                        except ValueError:
                            manual_frequency = None
                    pinyin = norm_pinyin(pinyin)
                    if not pinyin:
                        continue
                    identity = (simplified, traditional, pinyin)
                    entries[identity] = (
                        manual_frequency or max(1, frequencies.get(simplified, 1)),
                        definition,
                        pos,
                    )

    ordered = sorted(entries.items(), key=lambda item: (item[0][2], item[0][0], item[0][1]))
    syllables: dict[str, int] = {}
    with (output / "words.tsv").open("w", encoding="utf-8") as words, \
         (output / "translations.tsv").open("w", encoding="utf-8") as translations:
        words.write("# Derived from CC-CEDICT (CC BY-SA 4.0) and optional MIT-licensed jieba frequencies.\n")
        words.write("# Upstream SHA-256: " + raw_hash.hexdigest() + "\n")
        words.write("simplified\ttraditional\tpinyin\tfrequency\n")
        translations.write("# simplified\tpart_of_speech\tdefinition\tsource\n")
        for (simplified, traditional, pinyin), (frequency, definition, pos) in ordered:
            words.write(f"{simplified}\t{traditional}\t{pinyin}\t{frequency}\n")
            translations.write(f"{simplified}\t{pos}\t{definition}\tCC-CEDICT+reviewed\n")
            for syllable in pinyin.split():
                syllables[syllable] = syllables.get(syllable, 0) + max(1, frequency)

    with (output / "pinyin.tsv").open("w", encoding="utf-8") as handle:
        handle.write("# syllable\tfrequency\n")
        for syllable in sorted(syllables):
            handle.write(f"{syllable}\t{max(1, syllables[syllable])}\n")

    ngram_path = Path(args.ngram)
    if ngram_path.exists():
        (output / "ngram.tsv").write_text(ngram_path.read_text(encoding="utf-8"), encoding="utf-8")
    else:
        (output / "ngram.tsv").write_text("# type\tcontext\tsecond\ttoken\tcount\n", encoding="utf-8")

    source = {
        "cc-cedict-sha256": raw_hash.hexdigest(),
        "entries": len(ordered),
        "frequencies": "wordfreq+jieba" if args.wordfreq and args.jieba else (
            "wordfreq" if args.wordfreq else ("jieba" if args.jieba else "absent")
        ),
    }
    print(source)
    return 0


if __name__ == "__main__":
    sys.exit(main())
