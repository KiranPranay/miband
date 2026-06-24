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
| `findings-02.md` | Notify deep-dive (HR/fetch/battery/device-model). *(in progress)* |

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
| Test chunked hypothesis | ✅ refuted for MB6 (GB); Notify confirm pending |
| Realtime HR spec | ✅ from GB; ⏳ Notify confirm |
| Activity/HR-history/SpO2 fetch spec | ⏳ partial; exact MB6 layout pending |
| Battery spec | ✅ from GB; ⏳ Notify confirm |
| Implement HR (realtime) in Dart | ⏳ pending findings-02 |
| Implement battery + fetch fixes | ⏳ pending |
| Verify on device (log checklist) | ⏳ pending |

## Iteration log
- **01** (2026-06-24): decompile setup, GB extraction, Notify map, hypothesis refuted.
- **02**: Notify deep-dive (next).
