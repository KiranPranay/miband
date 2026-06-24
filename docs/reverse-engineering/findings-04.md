# Findings 04 — adb harness setup + baseline hardware run

**Date:** 2026-06-24
**Iteration goal:** Make the gated hardware test drivable over adb with no manual
taps, run a real baseline against the worn-or-not band on the Pixel 9a, and capture
the actual `MB6TEST` outcome of each gate — especially the live unknown, Gate 3
(`0x2A37` CCCD enable).

## 1. Environment (verified)
- `adb` at `/home/pranay/Android/Sdk/platform-tools/adb`; device `55211XEBF1RB28`
  (Pixel 9a, Android 17 / API 37) authorized.
- `flutter devices` lists the Pixel as a valid target. Branch
  `reverse-engineer-mb6-protocol`, package `com.example.band`.

## 2. Harness added (Step 0, committed `2e6e799`)
- `MainActivity.kt`: `run_hwtest` intent extra → `band/hwtest` MethodChannel
  (hot `onNewIntent` push + cold `checkLaunchTrigger` drain).
- `main.dart`: wires the channel, waits ≤60 s for auth, then calls
  `runHardwareTestSession()`.
- Runner: added the one-line `MB6TEST SUMMARY p=.. s=.. gates=[..] fw=..` and a
  best-effort firmware read (DIS `0x180A/0x2A26`).
- `capture-logs.md`: exact install/launch/trigger/capture commands. Captures land
  in `docs/reverse-engineering/logs/` (git-ignored).

Trigger command (no taps):
`adb shell am start -n com.example.band/.MainActivity --ez run_hwtest true`

## 3. Baseline run — real capture
Log: `logs/run-baseline-20260624-230700.log`. Connected + authed cleanly
(`Authentication SUCCESS! … First byte: 0x31`), then:

```
MB6TEST GATE0: PASS — fee0, fee1, 180d, 180f all present        (12 services)
MB6TEST GATE1: PASS — authenticated (legacy AES-ECB, no 0xFF)
MB6TEST GATE2: fee0/0x0006 raw=0f 2b 00 ea 07 06 15 00 04 24 ...
MB6TEST GATE2: PASS — battery 43% via fee0/0x0006 byte[1] — canonical path CONFIRMED
MB6TEST GATE3: 0x2A37 props read=false write=false notify=true indicate=false;
              0x2A39 props write=true writeNR=false
MB6TEST GATE3: FAIL — setNotifyValue(0x2A37) threw FlutterBluePlusException
              code=3 desc="GATT_WRITE_NOT_PERMITTED" … theory REFUTED
MB6TEST GATE6: raw(0B) first32:
MB6TEST GATE6: FAIL — no samples parsed …
MB6TEST SUMMARY p=3 s=2 gates=[0:P 1:P 2:P 3:F 4:S 5:S 6:F] fw=unknown
```

### What this proves
- **The harness works**: one adb command drives connect → auth → gates →
  parseable SUMMARY, fully captured in logcat.
- **Battery fix CONFIRMED on hardware** (Gate 2, `fee0/0x0006` byte[1] = 43%).
- **Gate 3 — the "post-auth sequencing" theory is REFUTED with captured proof.**
  `0x2A37` advertises `notify=true`, yet enabling its CCCD returns
  `GATT_WRITE_NOT_PERMITTED (code=3)` even though auth completed first.
- **Gate 6** returned 0 bytes (separate issue — likely "no new data since last
  sync" or a fetch trigger problem; it is downstream of Gate 3, so deferred).

## 4. Diagnosis of the earliest failing gate (Gate 3)
Evidence gathered (no guessing):
- `adb shell dumpsys bluetooth_manager`: **"Mi Smart Band 6" is already bonded**
  (Bonded devices: 2; `app_if: 88, appName: com.example.band, transport: LE`).
- The GATT error is **`code=3` (WRITE_NOT_PERMITTED)** — *not* `code=5`
  (INSUFFICIENT_AUTHENTICATION) or `code=15` (INSUFFICIENT_ENCRYPTION).

⇒ **Bonding/encryption is NOT the cause** (bond exists; code≠5/15). `code=3` means
the attribute itself refuses the write in the current state — i.e. a **prerequisite
command must unlock the standard HR characteristic for third-party access**.

This matches Gadgetbridge `HuamiService.COMMAND_ENABLE_HR_CONNECTION = 06 1f 00 01`
("expose HR to third-party apps", written to config char `fee0/0x0003`). The
official Mi Fit app has inherent HR access; a third-party GATT client like ours must
flip that gate before `0x2A37`'s CCCD becomes writable. findings-02 saw Notify *not*
need it — but Notify may already hold that grant or send it elsewhere; our captured
`code=3` says **this** firmware gates us.

## 5. Hypothesis for iteration 1 (→ findings-05)
**One variable:** before enabling `0x2A37` notify, write `06 1f 00 01` to
`fee0/0x0003` (enable HR / expose to third party). The fix lands in the **real HR
path** (`_setupHeartRate`) and the runner's Gate 3.
**Next line to watch:** `MB6TEST GATE3: PASS — 0x2A37 CCCD enabled — no
GATT_WRITE_NOT_PERMITTED`.
If it still fails `code=3`, the next variable is writing the `0x2A39` start command
*before* the CCCD enable; if it flips to `code=5/15`, revisit encryption/bond.

## 6. Open items
- Gate 6 zero-bytes: revisit after HR works (could be genuine "already synced").
- `fw=unknown`: MB6 does not expose DIS `0x2A26`; acceptable (Huami reports
  firmware via a private command we don't issue).
