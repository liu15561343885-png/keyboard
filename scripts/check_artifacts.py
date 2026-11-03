#!/usr/bin/env python3
"""Validate bundled artifact hashes and app configuration before a release."""
from __future__ import annotations

import base64
import hashlib
import json
import plistlib
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "Resources" / "Generated"
REQUIRED = [
    "pinyin.bin",
    "dictionary.zh-en.bin",
    "dictionary.en-zh.bin",
    "lm.bigram.bin",
    "lm.trigram.bin",
]
errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)
    print("FAIL:", message, file=sys.stderr)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")
        return {}


def main() -> int:
    for name in REQUIRED + ["candidate_scorer.mlmodel", "candidate_scorer.model.json", "dataset.json", "NOTICE.txt"]:
        if not (DATA / name).exists():
            fail(f"missing generated artifact: {name}")

    dataset = load_json(DATA / "dataset.json")
    model_meta = load_json(DATA / "candidate_scorer.model.json")
    for name, expected in dataset.get("files", {}).items():
        path = DATA / name
        if not path.exists():
            fail(f"dataset references missing file: {name}")
        elif sha256(path) != expected:
            fail(f"dataset hash mismatch: {name}")

    model_path = DATA / "candidate_scorer.mlmodel"
    if model_path.exists() and model_meta.get("sha256") != sha256(model_path):
        fail("candidate_scorer.model.json hash does not match the model")

    with (ROOT / "App" / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("PBDataVersion") != dataset.get("dataVersion"):
        fail(f"App PBDataVersion {info.get('PBDataVersion')!r} != dataset {dataset.get('dataVersion')!r}")
    if info.get("PBModelVersion") != model_meta.get("modelVersion"):
        fail("App PBModelVersion != model metadata version")
    manifest_url = info.get("PBManifestURL", "")
    if manifest_url and not str(manifest_url).startswith("https://"):
        fail("PBManifestURL must be empty or HTTPS")

    public_key = (ROOT / "Resources" / "UpdatePublicKey.txt").read_text(encoding="utf-8").strip()
    try:
        if len(base64.b64decode(public_key, validate=True)) != 32:
            fail("UpdatePublicKey.txt is not a 32-byte Ed25519 public key")
    except Exception:
        fail("UpdatePublicKey.txt is not valid base64")

    app_entitlements = plistlib.loads((ROOT / "App" / "PrivateKeyboard.entitlements").read_bytes())
    ext_entitlements = plistlib.loads((ROOT / "KeyboardExtension" / "KeyboardExtension.entitlements").read_bytes())
    app_groups = app_entitlements.get("com.apple.security.application-groups", [])
    ext_groups = ext_entitlements.get("com.apple.security.application-groups", [])
    if app_groups != ext_groups or len(app_groups) != 1:
        fail("app and extension App Group entitlements do not match")
    support = (ROOT / "SharedCore/Sources/PrivateKeyboardCore/Support/SharedSupport.swift").read_text(encoding="utf-8")
    match = re.search(r'appGroupIdentifier\s*=\s*"([^"]+)"', support)
    if not match or not app_groups or match.group(1) != app_groups[0]:
        fail("SharedConstants.appGroupIdentifier does not match entitlements")

    example = load_json(ROOT / "docs" / "manifest.example.json")
    if example.get("dataVersion") != dataset.get("dataVersion"):
        fail("example manifest dataVersion does not match dataset")
    for item in example.get("files", []):
        path = DATA / item.get("name", "")
        if not path.exists():
            fail(f"example manifest references missing file: {item.get('name')}")
        elif path.stat().st_size != item.get("size") or sha256(path) != item.get("sha256"):
            fail(f"example manifest hash/size mismatch: {item.get('name')}")

    privacy = load_json(ROOT / "Resources" / "PrivacyInfo.xcprivacy")
    if privacy.get("NSPrivacyTracking") is not False or privacy.get("NSPrivacyCollectedDataTypes") != []:
        fail("privacy manifest must declare no tracking and no collected data")

    if errors:
        print(f"{len(errors)} artifact/config error(s)", file=sys.stderr)
        return 1
    print("artifact/config checks passed")
    print(f"dataVersion={dataset.get('dataVersion')} words={dataset.get('wordCount')} model={model_meta.get('modelVersion')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
