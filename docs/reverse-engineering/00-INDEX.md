# Reverse-Engineering Mi Band 6 — Index & Status

Goal: make heart rate (realtime + history), activity, and battery work on Mi Band 6
by extracting the real wire protocol from the **Notify** (`com.mc.miband1`) and
**Mi Fit** APKs, cross-checked against **Gadgetbridge**, then fixing our Dart code.

## Documents
| File | Purpose |
|---|---|
| `protocol-mb6.md` | **Authoritative spec** — UUIDs, opcodes, byte layouts, sources. |
| `diff-our-vs-correct.md` | Living "we do X / correct is Y" table. |
| `findings-01.md` | Setup, Gadgetbridge extraction, Notify package map, hypothesis test. |
| `findings-02.md` | Notify deep-dive (HR/fetch/battery/device-model) + implementation. |
| `findings-03.md` | Hardware test-session instrumentation (gated runner + auto-probe). |
| `verification-checklist.md` | Per-claim → log-line checklist to confirm fixes on the real band. |
| `hardware-test-session.md` | **Runnable** gated session guide (gates 0→6) for the physical band. |
| `test-results-NN.md` | Per-run results template (fill after each hardware run; never overwrite). |

## Headline result (findings-01)
- **Mi Band 6 = legacy Huami protocol**, *not* the 2021 chunked channel.
- The task's "HR runs over chunked `0x0016/0x0017`" hypothesis is **REFUTED** for
  MB6 (Gadgetbridge evidence). Session-key derivation is **not needed**.
- Real HR path = standard `0x180D` service: write `15 01 01` to `0x2A39`, read
  `0x2A37` notifications.
- Our auth is already correct (legacy AES-ECB) and must stay unchanged.

## Status checklist
| Item | Status |
|---|---|
| Toolchain (jadx/apktool) + decompile Notify | ✅ done |
| Gadgetbridge clean-room reference | ✅ extracted |
| Locate Notify protocol packages | ✅ mapped (`x5/`, `com/mc/miband1/bluetooth/`) |
| Test chunked hypothesis | ✅ refuted for MB6 (GB **and** Notify) |
| Realtime HR spec | ✅ confirmed (GB + Notify) incl. keep-alive ping |
| Activity/HR-history/SpO2 fetch spec | ✅ confirmed (8-byte layout, correct types) |
| Battery spec | ✅ confirmed (`fee0/0x0006`) |
| Implement HR (realtime + one-shot) in Dart | ✅ done (`ble_manager.dart`) |
| Implement battery + activity-fetch fixes | ✅ done |
| Hardware test-session runner (gates 0→6, halt-on-fail) | ✅ done (`hardware_test_session.dart`) |
| Gate-5 keep-alive auto-probe (12/8/15 s) | ✅ done |
| Verify on device (run gated session) | ⏳ pending real-device run → fill `test-results-01.md` |

## Iteration log
- **01** (2026-06-24): decompile setup, GB extraction, Notify map, hypothesis refuted.
- **02** (2026-06-24): Notify deep-dive confirmed legacy HR/fetch/battery + keep-alive;
  enum contradiction adjudicated (MB6 = `MILI_PANGU`); implemented HR realtime +
  one-shot, battery `fee0/0x0006`, 8-byte activity samples + HR-from-activity, SpO2
  type fix. Code in `ble_manager.dart` + `activity_fetcher.dart`.
- **03** (2026-06-24): hardware test-session instrumentation — gated runner
  (`hardware_test_session.dart`) running gates 0→6 halt-on-fail with one greppable
  `MB6TEST GATEn` banner each, capture-on-fail dumps (Gate 3 GATT code, Gate 6 raw
  hex), and a Gate-5 keep-alive auto-probe (12→8→15 s). Trigger in Settings →
  Developer. Adds `hardware-test-session.md` + `test-results-01.md` template.
  No protocol opcodes changed.
