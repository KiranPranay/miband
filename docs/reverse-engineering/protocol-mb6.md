# Mi Band 6 — Reconstructed BLE Protocol (authoritative spec)

> Every assertion cites its source: **GB** = Gadgetbridge class:line,
> **NOTIFY** = decompiled `com.mc.miband1` class, **MIFIT** = `com.xiaomi.hm.health`.
> Items not yet cross-confirmed are tagged **UNVERIFIED**.

## 0. TL;DR — which protocol family is Mi Band 6?

**Mi Band 6 is a LEGACY Huami device**, the same protocol family as Mi Band 4/5.
It is **not** a "Huami 2021 / ZeppOS" chunked device. Decision evidence:
`HuamiSupport.force2021Protocol()` defaults `false` and is not overridden by
`MiBand6Support`/`MiBand5Support` (**GB** `HuamiSupport.java:3961`,
`MiBand6Support.java`). That single flag is what would have switched auth to ECDH
and data to the `0x0016/0x0017` chunked channel. It stays off for MB6.

Consequences:
- **Auth** = legacy AES-ECB challenge on `fee1/FEC1` (our app already does this and
  it works).
- **Realtime HR** = standard GATT Heart-Rate service `0x180D` (`0x2A39` control,
  `0x2A37` measurement).
- **Activity/HR-history/SpO2 fetch** = legacy `fee0/0x0004`(control)+`0x0005`(data).
- **Battery** = Huami `fee0/0x0006` (and/or standard `0x180F/0x2A19`).
- The chunked `0x0016/0x0017` channel is **not used**. Its full spec is kept in the
  Appendix for completeness only.

## 1. Services & characteristics

### 1.1 Huami private service `fee0` — `0000fee0-0000-1000-8000-00805f9b34fb`
Characteristic UUIDs are `0000NNNN-0000-3512-2118-0009af100700`
(**GB** `HuamiService.java:43-58`):

| `NNNN` | Name | Props | Use |
|---|---|---|---|
| `0003` | configuration | write/notify | config commands (`0x06 …`), fitness goal, time format |
| `0004` | activity **control** | write/notify | fetch control opcodes |
| `0005` | activity **data** | notify | fetch data stream |
| `0006` | battery info | read/notify | battery level + charge state |
| `0007` | realtime steps | read/notify | live steps/distance/calories |
| `0008` | user settings | write | user profile (age/height/weight/sex) |
| `0010` | device events | notify | button/event push |
| `0016` | chunked-2021 **write** | write | *(MB6: unused)* |
| `0017` | chunked-2021 **read** | notify | *(MB6: unused)* |
| `0020` | chunked (old) / alert | write | custom notifications (our `AlertManager`) |

### 1.2 Auth service `fee1` — char `fec1` (`…FEDD…`? no: `fee1`/`fec1` per our app)
Used only for the legacy handshake.

### 1.3 Standard Heart-Rate service `0x180D` — `0000180d-0000-1000-8000-00805f9b34fb`
| UUID | Name | Props |
|---|---|---|
| `00002a37-…` | HR Measurement | notify |
| `00002a39-…` | HR Control Point | write |

(**GB** `GattCharacteristic.java:80,82`.)

### 1.4 Standard Battery service `0x180F` — char `0x2A19` (read/notify)

## 2. Authentication (legacy, AES-ECB) — **WORKING in our app, do not change**

Source: **GB** `operations/init/InitOperation.java`; matches our
`ble_manager.dart` `_startAuthHandshake`/`_handleAuthResponse`.

```
→ FEC1: 01 <authFlags> <16-byte auth key>
← FEC1: 10 01 01                       (key accepted)   [or 10 01 04 = rejected]
→ FEC1: 02 <authFlags>                 (request challenge)
← FEC1: 10 02 01 <R0..R15>             (16 random bytes)
   enc = AES_ECB_NoPadding(authKey, R0..R15)
→ FEC1: 03 <cryptFlags> <enc0..enc15>
← FEC1: 10 03 01                       (AUTH SUCCESS)    [or 10 03 04 = key mismatch]
```
No session key, no post-auth encryption.

## 3. Realtime heart rate  ✅ (the fix)

Source: **GB** `HuamiSupport.java:1509-1554, 594-597, 2181-2193`,
`MiBandService.java:186-187`. **NOTIFY confirmation: pending (findings-02).**

**Characteristics:** control = `0x2A39`, measurement/notify = `0x2A37` (service `0x180D`).

**Command bytes → `0x2A39`:**
| Action | Bytes |
|---|---|
| stop continuous | `15 01 00` |
| **start continuous** | `15 01 01` |
| stop manual | `15 02 00` |
| **start manual (one-shot)** | `15 02 01` |

**Start continuous realtime HR:**
1. enable notifications on `0x2A37`
2. write `15 02 00` (stop manual) to `0x2A39`
3. write `15 01 01` (start continuous) to `0x2A39`

**One-shot HR test:** notify `0x2A37` → `15 01 00` → `15 02 00` → `15 02 01`.

**Stop:** write `15 01 00` to `0x2A39` (+ disable `0x2A37` notify).

**Parse `0x2A37` notification:** if `len==2 && b[0]==0` ⇒ `bpm = b[1] & 0xff`.
(Some firmwares also send `len>2` with a flags byte per BT HR spec — handle both:
if `b[0] & 0x01` the value is uint16 at `b[1..2]`, else uint8 at `b[1]`.) **UNVERIFIED** for MB6 — confirm in 02.

**Keep-alive:** continuous mode appears self-sustaining (GB sends no `0x16` ping).
**UNVERIFIED** — confirm whether Notify pings; if HR stops after ~30 s add a
periodic re-issue of `15 01 01` or a `0x16` ping.

## 4. Battery

Source: **GB** `HuamiService.java:46`, `HuamiSupport.java:546,601,2511`,
`HuamiBatteryInfo.java`.

- Read + notify `fee0/0x0006`.
- Payload layout (`HuamiBatteryInfo`): `byte[1]` = level %, `byte[2]` = charge
  state (0 normal, 1 charging). (**confirm exact offsets in 02**.)
- `0x180F/0x2A19` (our current path) returns level in `byte[0]`; keep as fallback.

## 5. Activity / HR-history / SpO2 fetch (legacy char-based)

Source: **GB** `operations/fetch/AbstractFetchOperation.java`,
`FetchActivityOperation.java`; chars `fee0/0x0004`+`0x0005`
(**GB** `HuamiService.java:44-45`). MB6 sample size = **8 bytes**
(**GB** `MiBand6Support.java:75`). **NOTIFY confirmation + exact MB6 layout: pending (findings-02).**

High-level handshake (our `activity_fetcher.dart` already follows this shape):
```
→ 0004: 01 <type> <year_lo year_hi month day hour min> 00 <tzQuarters>   (start)
← 0004: 10 01 01 <len32 LE> <sampleSize?> ...                            (accepted + count)
→ 0004: 02                                                              (begin transfer)
← 0005: <counter> <payload…> (repeated)
← 0004: 10 02 01                                                        (transfer done)
→ 0004: 03                                                              (ack/stop)
```
**Open:** exact `type` values (activity vs HR vs SpO2), the MB6 8-byte sample
layout, and the precise data-stream framing — to be pinned down in findings-02.

## 6. Time, display, user info, fitness goal (config char `fee0/0x0003`)
- Time sync: GB writes the 11-byte time blob to the **Current Time** char
  (`0x2A2B`) — our `_syncTime` matches. **(confirm char in 02.)**
- Config commands begin `0x06` (`ENDPOINT_DISPLAY`) and go to `fee0/0x0003`.
- `COMMAND_ENABLE_HR_CONNECTION = 06 1f 00 01` ("expose HR to 3rd-party apps")
  goes to **`0x0003`** (**GB** `HuamiService.java:155`) — *not* `0x0008` as our
  old HR attempt did. Optional for realtime HR.

---

## Appendix A — Huami-2021 chunked transport (NOT used by MB6; spec for completeness)

Kept because Notify implements it (it supports MB7) and the task asked us to spec
it. Sources: **GB** `Huami2021ChunkedEncoder.java`, `Huami2021ChunkedDecoder.java`,
`InitOperation2021.java`, `CryptoUtils.java`.

- Write `fee0/0x0016`, notify `fee0/0x0017`.
- **First-chunk frame (extended/2021):**
  `03 | flags | 00 | handle | count | len(4 LE) | type(2 LE) | payload…`
  Continuation chunks: `03 | flags | 00 | handle | count | payload…`.
  flags: `0x01` first, `0x02` last, `0x04` needs-ack, `0x08` encrypted.
- **Encryption** (extended+encrypt): `messageKey[i] = sessionKey[i] ^ handle`;
  `plain = data | seqNr(4 LE) | CRC32(data|seqNr)(4 LE)` zero-padded to /16;
  ciphertext = `AES/ECB/NoPadding(messageKey, plain)`; `seqNr++` per message.
- **Session key** from ECDH-B163 auth (endpoint `0x0082`):
  `sessionKey[i] = sharedEC[i+8] ^ authKey[i]`,
  `seqNr = LE32(sharedEC[0..3])`. Double-encrypted-random proof exchange.
- **Decoder** mirrors the encoder; on the last encrypted chunk it AES-decrypts and
  truncates to the declared length, then dispatches by `type`.

> If a *future* device (or a firmware that rejects legacy HR) turns out to need
> this, the `Huami2021Chunked` Dart class can be implemented from this appendix.
> For Mi Band 6 it is intentionally **not** wired up.
