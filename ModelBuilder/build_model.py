#!/usr/bin/env python3
"""Train the tiny local candidate ranker and export a Core ML mlmodel.

The training set is synthetic and derived from explicit product priors. It does
not contain user input, keystrokes, personal word frequencies, or speech data.
The exported model has nine numeric inputs and one 0...1 score output.
"""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import coremltools as ct
import numpy as np
from sklearn.linear_model import LinearRegression

FEATURES = [
    "baseFrequency",
    "userFrequency",
    "recency",
    "bigram",
    "trigram",
    "pinyinMatch",
    "translationAvailability",
    "candidateLength",
    "contextLength",
]
MODEL_VERSION = "micro-linear-1"
WEIGHTS = np.array([0.18, 0.20, 0.10, 0.12, 0.15, 0.30, 0.03, -0.02, 0.03])
BIAS = -0.05


def synthetic_target(x: np.ndarray) -> np.ndarray:
    linear = x @ WEIGHTS + BIAS
    # A small, explicitly local interaction: a user-learned word matters more
    # when there is already a two-word context.
    interaction = 0.04 * x[:, 1] * x[:, 8]
    return np.clip(linear + interaction, 0.0, 1.0)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="Resources/Generated/candidate_scorer.mlmodel")
    parser.add_argument("--metadata", default="Resources/Generated/candidate_scorer.model.json")
    parser.add_argument("--samples", type=int, default=40000)
    parser.add_argument("--seed", type=int, default=20261103)
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    x = rng.random((args.samples, len(FEATURES)))
    # Emphasis on realistic sparse context: most bigrams/trigrams are absent.
    x[:, 3] = np.where(rng.random(args.samples) < 0.55, 0.0, x[:, 3])
    x[:, 4] = np.where(rng.random(args.samples) < 0.75, 0.0, x[:, 4])
    x[:, 1] = np.where(rng.random(args.samples) < 0.75, 0.0, x[:, 1])
    x[:, 2] = np.where(rng.random(args.samples) < 0.75, 0.0, x[:, 2])
    y = synthetic_target(x)
    y = np.clip(y + rng.normal(0, 0.015, args.samples), 0.0, 1.0)

    regressor = LinearRegression().fit(x, y)
    r2 = regressor.score(x, y)

    model = ct.converters.sklearn.convert(
        regressor,
        input_features=FEATURES,
        output_feature_names="score",
    )
    model.version = MODEL_VERSION
    model.short_description = "PrivateKeyboard local candidate ranker (9 numeric features, CPU)."
    model.license = "Apache-2.0"
    model.author = "PrivateKeyboard contributors"
    model.user_defined_metadata.update(
        {
            "model_version": MODEL_VERSION,
            "training_data": "synthetic_priors_no_user_data",
            "feature_schema": ",".join(FEATURES),
            "output": "score",
            "privacy": "No user text, keystrokes, context, or personal frequencies are used.",
            "rollback": "Install a new signed model, or roll back to the previous dataset.",
        }
    )

    model_path = Path(args.out)
    model_path.parent.mkdir(parents=True, exist_ok=True)
    model.save(str(model_path))
    digest = hashlib.sha256(model_path.read_bytes()).hexdigest()

    metadata = {
        "modelVersion": MODEL_VERSION,
        "fileName": model_path.name,
        "sha256": digest,
        "size": model_path.stat().st_size,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "features": FEATURES,
        "output": "score",
        "framework": f"Core ML (coremltools {ct.__version__})",
        "training": "synthetic_local_priors",
        "samples": args.samples,
        "r2": round(float(r2), 6),
        "coefficients": [round(float(v), 6) for v in regressor.coef_],
        "intercept": round(float(regressor.intercept_), 6),
        "privacy": "No user input, keystrokes, context, speech data, or personal word frequencies were used.",
        "license": "Apache-2.0",
    }
    Path(args.metadata).parent.mkdir(parents=True, exist_ok=True)
    Path(args.metadata).write_text(json.dumps(metadata, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: metadata[k] for k in ["modelVersion", "sha256", "size", "r2"]}, indent=2))


if __name__ == "__main__":
    main()
