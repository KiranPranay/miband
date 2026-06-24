# Diff — Our code vs. Correct Mi Band 6 protocol (living document)

Legend: ✅ correct/fixed · ⚠️ partially wrong · ❌ wrong/missing · 🔵 confirm later

| # | Concern | Our code (before) | Correct (source) | Status |
|---|---|---|---|---|
| 1 | Auth handshake | legacy AES-ECB on `fee1/FEC1` — `ble_manager.dart` | legacy AES-ECB (`InitOperation`) — **GB**+**NOTIFY** | ✅ kept unchanged |
| 2 | Session key | none | none needed on legacy path | ✅ |
| 3 | Realtime HR — channel | stubbed; old attempt: `0x2A37` CCCD + cmds to `fee0/0x0008` | `0x2A37` notify + write to **`0x2A39`** — **GB**+**NOTIFY** | ✅ **fixed** (`_setupHeartRate`) |
| 4 | Realtime HR — start cmd | cmds to `fee0/0x0008` (inert) | `15 02 00` then `15 01 01` to `0x2A39` | ✅ **fixed** (`startRealtimeHeartRate`) |
| 5 | Realtime HR — parse | n/a | `bpm = data[1] & 0xFF` (7..249) | ✅ **fixed** (`_onHeartRateNotified`) |
| 6 | HR keep-alive | n/a | **`0x16` → `0x2A39` ≈14 s** — **NOTIFY** `x5/e.java` L() | ✅ **added** (12 s timer) |
| 7 | `GATT_WRITE_NOT_PERMITTED` on `0x2A37` | observed; blocked us | sequencing issue; enable notify post-auth + settle | ✅ addressed; 🔵 verify on device |
| 8 | Battery | `0x180F/0x2A19`, `data[0]` | canonical `fee0/0x0006`, level=`data[1]` — **GB**+**NOTIFY** | ✅ **fixed** (0x0006 + fallback) |
| 9 | Activity sample size | 4 bytes | **8 bytes** for MB6 — **GB**+**NOTIFY** | ✅ **fixed** (`_sampleSize=8`) |
| 10 | Activity fetch channel | `fee0/0x0004`+`0x0005` | same (legacy) | ✅ channel ok |
| 11 | Activity sample layout | `[cat,int,steps(2B)]`, HR=0 | `[cat,int,steps(1B),HR,_,sleep,deep,rem]` — **NOTIFY** | ✅ **fixed** (`_parseActivityData`) |
| 12 | HR history source | separate fetch type `0x0D` (= sleep!) | embedded at byte 3 of activity samples | ✅ **fixed** (`heartRatesFromSamples`) |
| 13 | SpO2 fetch type | `0x12` (= stress!) | **`0x25`** — **NOTIFY** | ✅ **fixed**; ⚠️ sample layout unverified |
| 14 | Metadata byte 7 | read as sample size | echoed start-timestamp | ✅ **fixed** (removed misread) |
| 15 | Chunked `0x0016/0x0017` | none | not used for HR/activity/battery on MB6 | ✅ (correctly absent) |
| 16 | User info char | `0x4f…` → `fee0/0x0008` | `fee0/0x0008` user settings | 🔵 confirm payload |
| 17 | Time sync | `0x2A2B` 11-byte blob | Current Time `0x2A2B` | ✅ likely |

Source tags: **GB**=Gadgetbridge, **NOTIFY**=com.mc.miband1.
