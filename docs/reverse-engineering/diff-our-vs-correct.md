# Diff — Our code vs. Correct Mi Band 6 protocol (living document)

Legend: ✅ correct · ⚠️ partially wrong · ❌ wrong/missing · 🔵 confirm in next iter

| # | Concern | Our code (file:line) | Correct (source) | Status |
|---|---|---|---|---|
| 1 | Auth handshake | legacy AES-ECB on `fee1/FEC1` — `ble_manager.dart:308-468` | legacy AES-ECB (`InitOperation`) — **GB** | ✅ keep |
| 2 | Session key | none | none needed on legacy path — **GB** `InitOperation` | ✅ |
| 3 | Realtime HR — channel | stubbed; old attempt used `0x2A37` CCCD + cmds to `fee0/0x0008` — `ble_manager.dart:817-844` | `0x2A37` notify + write `15 01 01` to **`0x2A39`** — **GB** `HuamiSupport.java:1526` | ❌ → fix |
| 4 | Realtime HR — start cmd | `[0x06,0x1f,0x00,0x01]`, `[0x14,01]`, `[0x15,00,01]` to `fee0/0x0008` | `15 02 00` then `15 01 01` to `0x2A39` | ❌ → fix |
| 5 | Realtime HR — parse | n/a | `len==2 && b[0]==0 ⇒ bpm=b[1]` — **GB** `:2181` | ❌ → add |
| 6 | HR keep-alive | n/a | none in GB (self-sustaining) | 🔵 confirm Notify |
| 7 | `GATT_WRITE_NOT_PERMITTED` on `0x2A37` | observed; blocked us | GB enables same CCCD fine → likely sequencing/lib issue | 🔵 confirm Notify |
| 8 | Battery | `0x180F/0x2A19`, `data[0]` — `ble_manager.dart:850-894` | canonical `fee0/0x0006` via `HuamiBatteryInfo`; `0x180F` ok as fallback — **GB** | ⚠️ add `0x0006` |
| 9 | Activity sample size | 4 bytes — `activity_fetcher.dart:258` | **8 bytes** for MB6 — **GB** `MiBand6Support.java:75` | ❌ → fix |
| 10 | Activity fetch channel | `fee0/0x0004`+`0x0005` — `activity_fetcher.dart` | same (legacy) — **GB** | ✅ channel ok |
| 11 | Activity fetch opcodes/layout | guessed (`type` 0x01/0x0D/0x12; 4-byte parse) | exact MB6 types + 8-byte layout — **GB**/**NOTIFY** | 🔵 pin down |
| 12 | HR "expose to 3rd party" cmd | `[0x06,0x1f,0x00,0x01]` → `fee0/0x0008` | → `fee0/0x0003` (config); optional — **GB** `:155` | ⚠️ move/remove |
| 13 | Chunked `0x0016/0x0017` | none | not used by MB6 | ✅ (correctly absent) |
| 14 | User info char | `0x4f…` → `fee0/0x0008` — `ble_manager.dart:766` | `fee0/0x0008` user settings — **GB** | 🔵 confirm payload |
| 15 | Time sync | `0x2A2B` 11-byte blob — `ble_manager.dart:494` | Current Time `0x2A2B` — **GB** | ✅ likely |

Updated each iteration. Source tags: **GB**=Gadgetbridge, **NOTIFY**=com.mc.miband1.
