# Findings 07 — Sign-key/ECDH auth implemented → ALL HR GATES PASS ✅

**Date:** 2026-06-25
**Result:** Heart rate works on the real Mi Band 6. Implementing the Huami 2021
**sign-key (ECDH) authentication** fully authenticated the band, which unlocked the
standard HR service and activity fetch that partial auth had locked. **All 7
hardware gates pass.** Log: `logs/run-iter6-signkey-20260625-002812.log`.

## What was built (ported from Gadgetbridge, unit-tested, then hardware-verified)
| Piece | File | Validation |
|---|---|---|
| NIST B-163 ECDH | `lib/core/ecdh_b163.dart` | bidirectional DH property (`shared(a,pubB)==shared(b,pubA)`) |
| Chunked transport (encoder/decoder) + CRC32 | `lib/core/huami2021_chunked.dart` | plaintext/encrypted, single/multi-chunk round-trips; CRC32 = canonical `0xCBF43926` |
| AES-ECB decrypt | `lib/core/encryption.dart` | (used by decoder) |
| Sign-key auth flow | `lib/core/huami2021_auth.dart` | hardware |

## The auth flow (captured)
```
Chunked transport (0x0016/0x0017) present — using Huami 2021 sign-key auth.
2021 auth: sending ECDH public key (52 B) to 0x0016 (mtu=247)   → 04 02 00 02 <pub48>
2021 auth payload (type=0x82): 10 04 01 78 c9 26 c5 76 …        ← random16 + remotePub48
2021 auth: shared session key derived; sending double-encrypted random  → 05 <enc1> <enc2>
2021 auth payload (type=0x82): 10 05 01 …                       ← success
2021 SIGN-KEY AUTHENTICATION SUCCESS!
```
Session key = `sharedEC[i+8] ^ authKey[i]`; `seqNr = LE32(sharedEC[0..3])`.

## Gate results (all PASS)
```
MB6TEST SUMMARY p=7 s=0 gates=[0:P 1:P 2:P 3:P 4:P 5:P 6:P] fw=unknown
```
- **Gate 3** — `0x2A37 CCCD enabled OK` — the `GATT_WRITE_NOT_PERMITTED` is **gone**.
  It was never a CCCD/bonding/sequencing problem; it was **incomplete auth**.
- **Gate 4** — `parsed BPM=68 (plausible 40..180)` — real heart rate.
- **Gate 5** — HR sustained past 60 s (events 0-30s=12, 30-60s=12, 60-90s=9) at the
  **12 s** keep-alive → the single-sourced 12 s value is **confirmed correct**.
- **Gate 6** — activity sample parsed with HR in byte 3 → 8-byte layout confirmed.
- HR readings vary physiologically (67–74 bpm) — a genuine pulse from the worn band.

## Real-app HR path (DoD: normal-use, not just the test runner)
After the gated session, the app restores normal realtime HR and the standard
listener reports live BPM:
```
HR: notifications enabled on 0x2A37.
HR: realtime measurement started.
HR notify: 00 49 -> 73 bpm        ← _onHeartRateNotified (no MB6TEST prefix)
```

## Why this is the correct architecture
Full sign-key auth elevates the connection's authorization so the band exposes the
**standard** `0x180D` HR service (`0x2A37`/`0x2A39`) and the legacy `fee0`
activity fetch. So HR/activity/battery ride the existing standard characteristics —
the encrypted chunked channel is needed only for **auth** on this firmware, not for
data. (Had the standard chars stayed locked, the chunked data endpoints were the
fallback; they proved unnecessary.)

## Corrections to earlier findings
- findings-01..05 assumed MB6 = legacy auth. **Wrong for this firmware** — it is a
  sign-key (`MILI_PANGU`, fw ≥ 1.0.4.1, encryption-capable) unit. The legacy auth
  on `fec1` was a non-validating hack; the canonical legacy auth on `0x0009` reached
  status `0x07` = sign-key-failed (findings-06), which pointed here.
- The first session's claim "the band doesn't expose `0x0016/0x0017`" was wrong —
  it does, and they carry the sign-key auth.

## Status: DONE
HR (realtime + history-from-activity), activity, and battery all work on the real
band. `protocol-mb6.md` + `diff-our-vs-correct.md` updated; `test-results-01.md`
filled from this run.
