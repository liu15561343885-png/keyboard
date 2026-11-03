# V2 Current Verification Status

Date: 2026-11-04
Commit: 0aab70c (stable UI build; earlier IPA b6b58a34)
Local IPA: `PrivateKeyboard-v2-unsigned.ipa`
SHA-256: `b6b58a34357b979e928a64a1f6e2cadd8d733a75fab15c11140d0396a44abeea`

## Verified in simulator

- Custom keyboard can be enabled via Settings and appears as `PrivateKeyboard`.
- 26-key: four rows visible, candidate capsule visible, idle candidates visible, no paste prompt.
- Candidate bar single line, no “本地候选”.
- Bottom row: `123 / 中 / 空格 / 换行`.
- Return key neutral gray.
- Nine-key grid: 18 controls, nonzero frames, within keyboard bounds (Catalyst smoke assertion).
- Tests: SwiftPM 40/40, iOS simulator 40/40, core-check 98/98 dev + 500-word holdout.
- Artifact/privacy checks pass.
- Release device build succeeds.

## Not visually verified in simulator

- Nine-key actual rendered screenshot after the latest explicit-frame layout.
- 46pt row / 8pt gap layout (reverted to 44/4 because it could not be verified).
- App appearance settings on the free-signing device.
- Native long-press punctuation popup.
- Touch behavior over long sessions.
- Per-key sound differences.

## Known gaps

- Keyboard is still positioned slightly higher than native.
- Bottom row uses `中`, not native emoji.
- Native number/symbol pages are not fully matched.
- “选拼音” currently expands candidates; native semantics not confirmed.
- Ranking model remains `micro-linear-1`; only n-gram data was enlarged.
- 500-word holdout is lexical, not human-authored blind.
- App Group entitlements are not present in the simulator/free-signing build; settings rely on named pasteboard.
- Occasional complete touch loss still needs device regression.

## Morning test checklist

1. 26-key four rows complete.
2. No paste prompt.
3. Candidate capsule and idle words.
4. Contextual following-word suggestions.
5. Fast repeated delete.
6. Long-press punctuation.
7. Nine-key columns aligned.
8. Nine-key `ABC` and “选拼音”.
9. Appearance settings apply after keyboard re-show.
