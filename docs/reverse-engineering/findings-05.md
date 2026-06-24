# Findings 05 — HR locked at the authorization layer (root cause: wrong auth char)

**Date:** 2026-06-24
**Iteration goal:** Drive Gate 3 (`0x2A37` CCCD) past `GATT_WRITE_NOT_PERMITTED`.
Two hypotheses tested on hardware and **both refuted**, leading to the real root
cause: we authenticate on the **wrong characteristic**.

## Iterations & evidence (all from real `adb logcat` captures in `logs/`)

### Iter 1 — "expose HR to third party" (`06 1f 00 01` → fee0/0x0003) — REFUTED
- Sub-bug found + fixed: config writes to `fee0/0x0003` were using
  write-**with**-response; the char only supports write-**without**-response
  (`PlatformException … WRITE property is not supported`). Fixed `_writeConfig`
  to pick the type from the characteristic's properties. After the fix the
  `06 1f 00 01` write succeeds.
- **But the `0x2A37` CCCD still returns `code=3`** after it. (`logs/run-iter1-*`.)

### Iter 2 — bonding / link encryption — REFUTED
- Captured: `bond state = none` initially; `createBond()` **succeeded**
  (`bond=bonded`, no pairing dialog). **CCCD still `code=3`** on the retry.
  (`logs/run-iter2-*`.) ⇒ encryption/bond is not the gate. Also confirmed
  `code=5`/`code=15` never appear — only `code=3` — so it is not an
  authentication/encryption ATT error.
- Harness improvement: a BT off/on reset before each run fixed the connection
  instability (band was terminating the link, HCI `reason 19`) so the gated
  session now completes in one connection.

### The decisive observation
- **The whole standard `0x180D` HR service is locked**, not just one CCCD:
  writes to the control point **`0x2A39` also fail `code=3`** (8 `code=3` events
  in the run, all on `0x2A37`/`0x2A39`).
- **Activity fetch (Gate 6 fallback) gets no response**: `cmd = 01 01 ea 07 06 17
  17 1c 00 16` is accepted (write-without-response) but the band never replies →
  60 s timeout (twice). So the activity-derived-HR fallback is *also* blocked.
- **What DOES work**: battery (`fee0/0x0006` = 43%), realtime steps
  (`Steps: 3933, 27 m, 102 kcal`), config writes (`fee0/0x0003`). I.e. basic
  reads/notifies on the Huami `fee0` service — but not the protected HR service
  and not activity-data delivery.

### Root cause — we authenticate on `fec1`, not the canonical `0x0009`
The `fee1` service exposes these characteristics (captured `CHAR UUID` logs):
`00000009-0000-3512-2118-0009af100700`, `fedd`,`fede`,`fedf`,`fed0`..`fed3`,
`0000fec1-0000-3512-2118-0009af100700`.

- **`00000009-…` is the canonical Huami/Mi-Band auth characteristic**
  (Gadgetbridge `UUID_CHARACTERISTIC_AUTH`; Notify legacy auth uses `0x0009`).
- **Our app authenticates on `fec1`** (`ble_manager.dart` `_handleConnected`
  selects the `fec1` char). On `fec1` the handshake is non-standard:
  ```
  → 01 00 <key>
  ← bf 23 f8 9d 0a 4d 2e b6 12 df 5a 1c 12 dd ec 26 25 25 52 16 …   (32 bytes!)
  (our V3 fallback) encrypt 32 bytes → 03 00 <enc>
  ← 31 19 d0 c8 …  (NOT the canonical 10 03 01)  → we ASSUME success
  ```
  The canonical flow is `01 .. key → 10 01 01 → 02 .. → 10 02 01 +16-rand →
  03 .. enc16 → 10 03 01`. We never see those, because `fec1` is the wrong char.

⇒ **Hypothesis (iter 3): authenticating on `0x0009` (canonical) gives a complete
auth and unlocks the protected HR service + activity-data responses.** The current
`fec1` auth grants only partial access (enough for battery/steps), which is why
the band withholds the `0x180D` service (`code=3`) and ignores activity fetches.

## Changes this iteration
- `ble_manager.dart`: `_writeConfig` now picks write-with/without-response from the
  characteristic properties (real bug fix). Reverted the refuted `06 1f 00 01`
  prerequisite from the HR path; added `currentBondState()` + `_ensureLinkEncrypted()`
  (bonding helper, kept — harmless and may matter later).
- `hardware_test_session.dart`: Gate 3 now logs bond state and, on `code=3`, runs
  `createBond()` + retry (the diagnostic that refuted bonding); added `_tryEnableCccd`.
- Harness (`scratchpad/hwtest.sh`): BT off/on reset for clean runs.

## Next (iter 3)
Point auth at the canonical `0x0009` char (fall back to `fec1` if absent) — a
contained, reversible change. **Next line to watch:** the canonical
`10 01 01` / `10 02 01` / `10 03 01` exchange in the log, then
`MB6TEST GATE3: PASS`. If auth fails on `0x0009`, revert to `fec1` (no harm — debug
build only; the band's key is never modified).
