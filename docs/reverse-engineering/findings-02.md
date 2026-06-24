# Findings 02 — Notify (`com.mc.miband1`) deep-dive: HR, fetch, battery, chunked audit

**Date:** 2026-06-24
**Iteration goal:** Independently confirm/refute the Gadgetbridge-derived spec against
the **Notify** app (which is known to work with the user's real Mi Band 6), extract
exact realtime-HR opcodes + keep-alive cadence, the MB6 8-byte sample layout, the
battery characteristic, and settle whether Notify ever drives MB6 over the chunked
`0x0016/0x0017` channel.

**Method:** 5 finder agents over the decompiled Notify tree
(`ref_apks/decompiled/notify_jadx/sources`), each output adversarially re-verified
against the cited source by a second agent (workflow `notify-mb6-protocol-extract`,
10 agents, ~706k tokens). One inter-agent contradiction (the MB6 device-enum
identity) was adjudicated by hand — see §6.

---

## 1. What I inspected
- Notify protocol classes (obfuscated): `x5/e.java` (main legacy Huami service,
  `class e extends b`), `x5/i.java` (legacy AES-ECB auth), `x5/i0.java` (all UUID
  constants), `x5/h.java` (standalone HR GATT client), `com/mc/miband1/bluetooth/
  BLEManager.java`, `com/mc/miband1/bluetooth/devices/b.java` (device enum),
  `com/mc/miband1/helper/b.java` (fetch buffering + sample parse),
  `com/mc/miband1/model/UserPreferences.java` (the `If()/Kb()/a()` gates),
  `r6/b.java` (battery parse), `n6/*`, `a0.java` (the 2021 gate).
- Cross-checked against Gadgetbridge `FetchActivityOperation.java`,
  `HuamiBatteryInfo.java`, `HuamiSupport.java`.

## 2. Realtime heart rate — **CONFIRMED legacy + keep-alive ping discovered**
Notify uses the **standard `0x180D` HR service**, not chunked, for MB6.
(`x5/i0.java`: `f90419y`=`0x2A37` measurement L83, `f90421z`=`0x2A39` control L86.)

| Action | Bytes → `0x2A39` | Source |
|---|---|---|
| start continuous (realtime) | `15 01 01` | `x5/e.java` `z0.run()` L1746 |
| stop continuous | `15 01 00` | `x5/e.java` `q()` L6845 |
| one-shot / manual | `15 02 01` | `x5/e.java` `y.run()` L1680 |
| sleep-HR detect on/off | `15 00 01` / `15 00 00` | `x5/e.java` `Y()` L4974/4977 |
| periodic auto interval | `14 <minutes>` (+ `FE 01 00 <m>` to `0x0003`) | `x5/e.java` `M()` L3831 |
| **keep-alive ping** | **`16`** | `x5/e.java` `L()` L3674 |

- **Continuous start sequence** (`z0.run()`, L1719-1748): enable notify on `0x2A37`,
  set ping-marker `K = now` (L1743), write `15 01 01` to `0x2A39` (L1746).
- **BPM parse:** ignore `byte[0]`; `bpm = byte[1] & 0xFF`; valid range **7..249**
  (else treated as 0/no-reading). `BLEManager.m1()` L3088-3092, `HeartMonitorData.
  cleanHeartValue()` L57. Identical to GB `handleHeartrate` (`HuamiSupport.java:2181`).
- **KEEP-ALIVE — the one thing Gadgetbridge's MB6 base did NOT show:** Notify sends a
  single byte **`0x16`** to `0x2A39` to keep continuous HR streaming. It is **not** a
  fixed timer; it is **driven off each incoming `0x2A37` notification**: in
  `BLEManager.l1()` (L2862-2879), when continuous mode (`C3()==1`) and `now - K >
  14000 ms`, it calls `V0(false) → c0.L()` → writes `0x16`. Effective cadence ≈ 14 s.
  ⇒ **We must send `0x16` to `0x2A39` ~every 14 s while realtime HR is active**, or
  the band may stop streaming.
- **`06 1f 00 01` is NOT a prerequisite** for the `0x2A37` CCCD enable. It is an
  independent config write on `fee0/0x0003` (`x5/e.java` `h3()` L5874) gated by a
  user pref. So our old code sending HR commands to `fee0/0x0008` was simply on the
  wrong characteristic entirely.
- **`GATT_WRITE_NOT_PERMITTED` puzzle:** Notify enables `0x2A37` notifications
  successfully on MB6 (post-auth, via the Nordic BLE request queue, init order
  `0x0016,0x0017,0x0009,0x0004,0x0005, 0x2A37+0x0010, 0x0007,0x0003,0x0006` —
  `x5/e.java` `v1()` L8802-8843). There is **no special unlock** before the CCCD
  write. ⇒ Our `WRITE_NOT_PERMITTED` is almost certainly a **sequencing / library
  timing issue** (writing the CCCD before auth/discovery settled, or a
  flutter_blue_plus descriptor quirk), **not** a protocol gate. Mitigation in the
  implementation: enable `0x2A37` notify *after* auth success and a short settle,
  log the characteristic's properties (notify vs indicate), and fall back to
  HR-from-activity-fetch if it still fails.
- There is also a **second, standalone HR GATT client** in Notify (`x5/h.java`) that
  opens its own connection and subscribes `0x2A37` directly via the CCCD `0x2902`
  descriptor (`01 00`) — a 24/7 background HR path. Not needed for our use case.

## 3. Activity / health-data fetch — **CONFIRMED legacy, 8-byte MB6 sample**
Over `fee0/0x0004` (control, `i0.M`) + `fee0/0x0005` (data, `i0.N`).

- **Start (→ `0x0004`):** `01 <type> <yr_lo yr_hi month day hour min> 00 <tz>`
  (10 bytes; `tz` = quarter-hours). `x5/e.java` `N2()` L4132. **Matches our code.**
- **Data types (2nd byte):** `01`=activity, `05`=HR/manual-HR history, `0D`=sleep,
  `12`=stress, `13`=stress-allday, **`25`=SpO2**, `26`=SpO2 variant, `07`=raw log.
  ⇒ **Our SpO2 type `0x12` is wrong (that's stress) → use `0x25`. Our HR-history
  type `0x0D` is wrong (that's sleep) → HR comes from the `0x01` activity stream
  (byte 3) or the `0x05` HR-history fetch.** (Note: GB labels `0x0D` as PAI; Notify
  labels it sleep — apps differ; either way `0x0D` is not HR.)
- **Metadata (← `0x0004`):** `10 01 01 | count(uint32 LE @3..6, excludes per-packet
  counter bytes) | start-ts(@7..14: yr@7-8, mon@9, day@10, hr@11, min@12, sec@13,
  tz@14)`. `x5/e.java` L7918-7928. ⇒ **Our `_expectedSampleSize = data[7]` is WRONG —
  byte 7 is the start-timestamp, not a sample size. Sample size is a fixed device
  property (8 for MB6), not transmitted.**
- **Per-packet (← `0x0005`):** `byte[0]` = sequence counter (drop), `byte[1..]` =
  payload, accumulated. `com/mc/miband1/helper/b.java` `r()` L302-305.
  **Matches our `_onDataReceived`.**
- **Flow:** after metadata write `02` to `0x0004` (`P2()` L4282); completion = `10 02
  xx` (len 3) on `0x0004` (L7895); ack = `03`.
- **MB6 sample = 8 bytes** (`com/mc/miband1/helper/b.java` `s()` L339-358; GB
  `createExtendedSample` L152-163 — byte-for-byte identical):

  | byte | field |
  |---|---|
  | 0 | category / kind |
  | 1 | intensity |
  | 2 | **steps (single byte 0-255 for the minute)** |
  | 3 | **heart rate** (cleaned: 0/255 ⇒ no-reading) |
  | 4 | unknown1 |
  | 5 | sleep |
  | 6 | deepSleep |
  | 7 | remSleep |

  Sample N timestamp = start + N minutes. ⇒ **Our parser uses 4-byte samples with a
  2-byte step field — both wrong for MB6.** HR history is *embedded here at byte 3*.

## 4. Battery — **CONFIRMED `fee0/0x0006`**
- MB6 (legacy class `x5.e`) reads + subscribes `fee0/0x0006` (`i0.O`). The standard
  `0x180F/0x2A19` path exists only in the ZeppOS subclass `x5.f` — **not** MB6.
- Parse (`r6/b.java` `e()`): `byte[0]`=flags, **`byte[1]`=level %**, `byte[2]`=charge
  state (present when flags bit0 set; `1`=charging). Matches GB `HuamiBatteryInfo`.
- Notify both does an explicit read **and** stays subscribed to notifications.
- ⇒ Our `0x180F/0x2A19` read (level in `byte[0]`) works as a fallback but the
  canonical MB6 source is `fee0/0x0006` with level in `byte[1]`.

## 5. Chunked-`0x0016/0x0017` audit — nuanced
- **HR, activity, battery never use the chunked channel on MB6** (all confirmed on
  standard/legacy chars above). The task's HR-over-chunked hypothesis stays
  **REFUTED**.
- However, Notify *can* route **encrypted config/handshake commands** (and an ECDH
  pairing) over `0x0016/0x0017` for MB6 **when** the band advertises encryption
  capability (`n6.b.d()==true`, protocol ≥ 2) **and** firmware ≥ `1.0.4.1`
  (`a0.j()`/`If()` gate). This is *not* required for operation: Gadgetbridge drives
  MB6 entirely in plaintext legacy, and **our app's plaintext auth + alerts + config
  already work**, which empirically proves our band does **not** enforce it.
  ⇒ We implement plaintext legacy. The encrypted-chunked command path is documented
  in `protocol-mb6.md` Appendix A as a *future-only* contingency.

## 6. Adjudicated contradiction — MB6 device enum identity
The two finder agents disagreed on which enum is Mi Band 6. Resolved from source
(`com/mc/miband1/bluetooth/devices/b.java`):

| enum | bandSource | `f23024a` case | display label |
|---|---|---|---|
| `G1 = MILI_PANGU` | 211 | 85 | **"Mi Band 6 NFC"** |
| `H1 = MILI_PANGU_L` | 212 | 86 | **"Mi Band 6"** |
| `f22953o2 = MILI_L66` | 262 | 101 | **"Mi Band 7"** |

⇒ **`MILI_L66` (id 262) is Mi Band 7, not Mi Band 6.** The *device-dispatch* finder
mislabeled it; the *chunked-audit* finder's identification (MB6 = `MILI_PANGU` G1/H1)
is correct, and that is why `If()` (the encryption/2021 gate) can match MB6. This
does **not** change the data-path conclusions (HR/activity/battery are
standard/legacy on every variant), only the chunked-command nuance in §5.

## 7. Hypothesis status (final)
- **Chunked `0x0016/0x0017` for HR on MB6: REFUTED** (both GB and Notify; high
  confidence, multiple cited methods). HR = standard `0x2A37/0x2A39`.
- **Session-key for HR/data: NOT NEEDED.** A session key exists only for the optional
  encrypted-command path, which our band doesn't require.
- **Keep-alive ping: CONFIRMED REQUIRED-by-Notify** — `0x16` to `0x2A39` ≈ every 14 s
  during realtime HR (new vs. findings-01's "probably none").

## 8. Changes made this iteration
- None to Dart yet (this file documents the extraction). Implementation follows in
  this same iteration's commit (see `findings-03`/code commit) — HR realtime via
  `0x2A37/0x2A39` + `0x16` keep-alive, activity 8-byte parse + correct types,
  battery `fee0/0x0006`.

## 9. Open questions / next goal
1. Implement and verify on the real band; confirm `0x2A37` CCCD now succeeds with
   correct post-auth sequencing (resolves the `WRITE_NOT_PERMITTED` empirically).
2. Confirm the keep-alive cadence is sufficient (does HR stop if we skip `0x16`?).
3. Decode SpO2 (`0x25`) and stress (`0x12/0x13`) sample payload layouts if we want
   those (separate Notify handlers `b1/c1`); HR + steps + sleep are fully decoded.
4. Confirm the fetch `tz` byte arithmetic matches ours (quarter-hours).
