# Findings 01 — Decompile setup, Gadgetbridge reference, Notify package map

**Date:** 2026-06-24
**Iteration goal:** Stand up the decompilation toolchain, extract the authoritative
Mi Band 6 post-auth protocol from Gadgetbridge (clean-room source), locate the
matching protocol packages inside the Notify APK, and **test the task's central
hypothesis** that HR/activity run over the Huami-2021 chunked channel
(`0x0016/0x0017`) on Mi Band 6.

---

## 1. What I inspected

### Tooling (all fetched into `tools/`, git-ignored)
| Tool | Version | Command |
|---|---|---|
| jadx | 1.5.0 | `tools/jadx/bin/jadx -d <out> --no-res -j 4 --show-bad-code base.apk` |
| apktool | 2.10.0 | `java -jar tools/apktool.jar d <apk>` (smali fallback, not yet needed) |
| Java | OpenJDK 21.0.11 | system |

### Inputs unpacked
- `ref_apks/notify/com.mc.miband1_21.7.2-2172_*.apkm` → unzipped to
  `ref_apks/decompiled/notify_apkm/` (split APKs). The code lives in
  `base.apk` (6 dex files, ~66 MB of bytecode).
- jadx decompiled `base.apk` → `ref_apks/decompiled/notify_jadx/sources/`
  (20,688 `.java` files, 217 MB).
- Gadgetbridge cloned (shallow) to `gadgetbridge/` from
  `https://codeberg.org/Freeyourgadget/Gadgetbridge.git` — used as the clean-room
  third source.

### Our Dart code (baseline)
- `lib/core/ble_manager.dart` (933 lines) — connection, auth V2/V3, post-auth init,
  HR stubbed at lines 817-844.
- `lib/core/activity_fetcher.dart` (334 lines) — legacy `fee0/0x0004`+`0x0005` fetch.
- `lib/core/encryption.dart` — AES/ECB/NoPadding (auth challenge only).

---

## 2. What I found — Gadgetbridge (authoritative, with citations)

### 2.1 Mi Band 6 uses the **LEGACY Huami protocol**, NOT the 2021 chunked protocol

Class chain: `MiBand6Support → MiBand5Support → MiBand4Support → … → HuamiSupport`.

- `HuamiSupport.force2021Protocol()`
  (`service/devices/huami/HuamiSupport.java:3961`) returns
  `getDeviceSpecificSharedPrefs(...).getBoolean("force_new_protocol", false)` —
  **default `false`**, and **neither `MiBand6Support` nor `MiBand5Support`
  override it**. (Verified: `MiBand6Support.java` has no override;
  `grep` for an override returns only the base definition.)
- `force2021Protocol()` is the single switch that selects:
  - **Auth**: `force2021Protocol()` → `InitOperation2021` (ECDH) else
    `InitOperation` (legacy AES-ECB). `HuamiSupport.java:411-419`.
  - **Chunked extended flags / encryption**: passed as the `extended_flags`
    argument to `Huami2021ChunkedEncoder.write(...)`. `HuamiSupport.java:3799`.

**⇒ For Mi Band 6, Gadgetbridge authenticates with the legacy AES-ECB challenge on
`fee1/FEC1` and never touches `0x0016/0x0017`.** This exactly matches our app's
*working* auth handshake in `ble_manager.dart` (`_startAuthHandshake`,
`_handleAuthResponse`, `_encryptAndSendStep3`).

### 2.2 Legacy auth (matches us) — `InitOperation`
- Send key: `[0x01, authFlags, <16-byte key>]` to `fee1/FEC1`
- Request challenge: `[0x02, authFlags]`
- Band replies: `[0x10, 0x02, 0x01, <16 random bytes>]`
- Encrypt the 16 random bytes with the auth key (AES/ECB/NoPadding)
- Send: `[0x03, cryptFlags, <16 encrypted bytes>]`
- Success: `[0x10, 0x03, 0x01]`

No session key is derived. The auth key **is** the only key, and it is **not**
used to encrypt any later traffic on the legacy path.

### 2.3 Realtime heart rate — standard GATT service `0x180D`
Source: `HuamiSupport.java:1508-1554`, `:594-597`, `:2181-2193`; UUIDs from
`service/btle/GattCharacteristic.java:80,82`; command bytes from
`devices/miband/MiBandService.java:186-187`.

- **Control point** = `00002a39-0000-1000-8000-00805f9b34fb` (`0x2A39`, standard
  HR Control Point), held as `characteristicHRControlPoint`
  (`HuamiSupport.java:421`).
- **Measurement / notify** = `00002a37-0000-1000-8000-00805f9b34fb` (`0x2A37`,
  standard HR Measurement).
- Command bytes (written to `0x2A39`):
  | Action | Bytes |
  |---|---|
  | stop continuous | `0x15 0x01 0x00` |
  | start continuous | `0x15 0x01 0x01` |
  | stop manual (one-shot) | `0x15 0x02 0x00` |
  | start manual (one-shot) | `0x15 0x02 0x01` |
- **Realtime sequence** (`onEnableRealtimeHeartRateMeasurement`,
  `HuamiSupport.java:1526`):
  1. `notify(0x2A37, true)`
  2. write `stopManual` (`0x15 0x02 0x00`) to `0x2A39`
  3. write `startContinuous` (`0x15 0x01 0x01`) to `0x2A39`
- **One-shot sequence** (`onHeartRateTest`, `HuamiSupport.java:1509`):
  `notify(0x2A37,true)` → `stopContinuous` → `stopManual` → `startManual`.
- **Parse** (`handleHeartrate`, `HuamiSupport.java:2181`): a `0x2A37`
  notification of `length==2 && value[0]==0` ⇒ `bpm = value[1] & 0xff`.
- **Keep-alive:** Gadgetbridge does **not** send a periodic `0x16` ping for Huami
  continuous mode (no such write found in `HuamiSupport`). Continuous mode is
  self-sustaining. (Older Mi Band 1/2 needed pings; Huami does not.) — *to be
  re-confirmed against Notify in findings-02.*

### 2.4 Battery — Huami char `fee0/0x0006`
- `UUID_CHARACTERISTIC_6_BATTERY_INFO = 00000006-0000-3512-2118-0009af100700`
  (`HuamiService.java:46`). Read + notify (`HuamiSupport.java:546,601`).
- Parsed by `HuamiBatteryInfo` (`getLevelInPercent`, charging state from byte 1).
- The standard `0x180F/0x2A19` battery service that our `_readBattery()` uses may
  also exist, but the canonical Huami path is `fee0/0x0006`. — *confirm in 02.*

### 2.5 Activity fetch — legacy char-based, `fee0/0x0004` (control) + `0x0005` (data)
- `UUID_CHARACTERISTIC_5_ACTIVITY_CONTROL = …0004…`,
  `UUID_CHARACTERISTIC_5_ACTIVITY_DATA = …0005…` (`HuamiService.java:44-45`).
- Implemented by `operations/fetch/FetchActivityOperation.java` +
  `AbstractFetchOperation.java`. Mi Band 6 sample size = **8 bytes**
  (`MiBand6Support.getActivitySampleSize() = 8`). *(Our `_parseActivityData`
  uses 4-byte samples — diverges; details to follow in a fetch-focused finding.)*

### 2.6 fee0 characteristic map (Huami legacy)
| UUID suffix | Constant | Purpose |
|---|---|---|
| `0x0003` | `UUID_CHARACTERISTIC_3_CONFIGURATION` | config / commands (`0x06 …`) |
| `0x0004` | `..._5_ACTIVITY_CONTROL` | activity fetch control |
| `0x0005` | `..._5_ACTIVITY_DATA` | activity fetch data |
| `0x0006` | `..._6_BATTERY_INFO` | battery |
| `0x0007` | `..._7_REALTIME_STEPS` | realtime steps |
| `0x0008` | `..._8_USER_SETTINGS` | user info |

### 2.7 The Huami-2021 chunked transport (for reference — used by MB7/ZeppOS, **not** MB6)
Captured in full because the task asked us to spec it and because Notify *does*
implement it (it supports MB7). Sources: `Huami2021ChunkedEncoder.java`,
`Huami2021ChunkedDecoder.java`, `InitOperation2021.java`, `CryptoUtils.java`,
`HuamiService.java:57-58`.

- Write char `00000016-…`, notify char `00000017-…`.
- Frame: `0x03 | flags | [0x00 | handle | count]` then (first chunk)
  `len(4 LE) | type(2 LE)`. flags: `0x01` first, `0x02` last, `0x04` needs-ack,
  `0x08` encrypted.
- Encryption (when used): per-message `messageKey[i] = sessionKey[i] ^ handle`,
  payload = `data | seqNr(4 LE) | CRC32(data|seqNr)(4 LE)` zero-padded to /16,
  **AES/ECB/NoPadding** (`CryptoUtils.encryptAES`).
- Session key comes from **ECDH (B-163)** auth: `finalSharedSessionAES[i] =
  sharedEC[i+8] ^ authKey[i]`; `encryptedSequenceNr` = first 4 bytes of `sharedEC`.
  Auth endpoint = `0x0082`. (`InitOperation2021.java:117-160`.)

This is documented in `protocol-mb6.md` §Appendix but is **NOT** the MB6 data path.

---

## 3. How it differs from our code (high level — full table in `diff-our-vs-correct.md`)

| Area | Our code | Correct (Gadgetbridge, legacy MB6) |
|---|---|---|
| Auth | legacy AES-ECB on `fee1/FEC1` ✓ | same ✓ — **keep as-is** |
| Realtime HR | **stubbed**; previously tried `0x2A37` CCCD + commands to `fee0/0x0008` | `notify(0x2A37)` + write `0x15 01 01` to **`0x2A39`**; parse `[0,bpm]` |
| HR "enable connection" cmd | sent `[0x06,0x1f,0x00,0x01]` to **`fee0/0x0008`** | that command belongs on **`fee0/0x0003`** (config); but is *not required* for realtime HR |
| Battery | standard `0x180F/0x2A19` | canonical Huami `fee0/0x0006` (0x180F may also work) |
| Activity sample size | 4 bytes | **8 bytes** for MB6 |
| Chunked `0x0016/0x0017` | (none) | **not used by MB6** |

---

## 4. Hypothesis status

> **Task hypothesis:** "On 2021 firmware, HR (and most app data) is NOT on
> `0x2A37`. It runs over the chunked transport on `fee0` characteristics `0x0016`
> (write) and `0x0017` (notify)."

- **REFUTED for Mi Band 6 (per Gadgetbridge).** Mi Band 6 is a legacy-protocol
  device: legacy AES-ECB auth (which is *exactly* why our auth already works,
  unmodified), HR over the standard `0x2A37/0x2A39` GATT service, activity over
  legacy `fee0/0x0004+0x0005`. The chunked `0x0016/0x0017` channel exists in the
  Huami stack but is gated behind `force2021Protocol()=true`, which MB6 never sets.
- **Session-key theory:** likewise **not applicable** to MB6. A shared session key
  is derived only on the ECDH (`InitOperation2021`) path. The legacy path uses the
  static auth key and encrypts **nothing** after the handshake.
- ⚠️ **One open empirical risk:** our previous attempt to enable `0x2A37`
  notifications returned `GATT_WRITE_NOT_PERMITTED (3)`. Gadgetbridge enables that
  exact CCCD on MB6 without trouble, so this is most likely a **sequencing/library
  issue** (e.g. writing the start command before/without notify, or a
  flutter_blue_plus descriptor quirk), **not** a protocol-channel issue. This must
  be confirmed against the Notify implementation (which definitely drives the
  user's real band) — see next iteration — before we conclude.

---

## 5. Changes made this iteration
- Added `tools/`, `ref_apks/decompiled/`, APK binaries to `.gitignore`.
- Created `docs/reverse-engineering/` with `00-INDEX.md`, `protocol-mb6.md`,
  `findings-01.md`, `diff-our-vs-correct.md`.
- **No Dart code changed** (per task: document first).

---

## 6. Open questions / next iteration goal (findings-02)
1. **Confirm against Notify** (`com.mc.miband1`, package `x5/`,
   `com/mc/miband1/bluetooth/`) — Notify works with the user's actual band, so it
   is the ground truth for the band's real behavior:
   - Does Notify treat **Mi Band 6** as a legacy or 2021 device? (device-model
     dispatch is in `com/mc/miband1/bluetooth/devices/b.java`.)
   - Exact realtime-HR opcodes + characteristics Notify uses for MB6 (HR refs in
     `x5/h.java`; HR `0x15` patterns in `x5/c.java`, `x5/e0.java`, `x5/f0.java`).
   - Whether Notify sends an HR keep-alive ping, and at what cadence.
   - Activity/HR-history fetch opcodes + MB6 sample layout (main service
     `x5/e.java`, 9355 lines).
   - Battery characteristic Notify reads.
2. Resolve the `GATT_WRITE_NOT_PERMITTED` puzzle definitively.
3. Then implement (HR realtime via `0x2A37/0x2A39`, fix sample size, battery) and
   verify against logs.

**Located Notify protocol map (for the next iteration):**
| Concern | Obfuscated location |
|---|---|
| Main Huami protocol service | `x5/e.java` (9355 L), `x5/e0.java`, `x5/f0.java`, `x5/g0.java` |
| Device model dispatch / MB6 | `com/mc/miband1/bluetooth/devices/b.java` |
| BLE manager / base service | `com/mc/miband1/bluetooth/BLEManager.java`, `BaseService.java` |
| Chunked `0016/0017` transport | `x5/o0.java`, `x5/i0.java`, `p9/e.java`, `gc/a.java` |
| HR (`2A37`) | `x5/h.java` |
