# Hardware Test Results — Run 01 (Huami 2021 sign-key auth)

Filled from the real capture `logs/run-iter6-signkey-20260625-002812.log`.

## Run metadata
| Field | Value |
|---|---|
| Date / time | 2026-06-25 00:28 |
| Phone | Pixel 9a (tegu), Android 17 / API 37, adb `55211XEBF1RB28` |
| Band | Mi Smart Band 6 (`MILI_PANGU`), worn snug, wear-detect active |
| Band firmware | `fw=unknown` (band doesn't expose DIS `0x2A26`) |
| App branch / commit | `reverse-engineer-mb6-protocol`, sign-key auth build |
| Auth used | **Huami 2021 sign-key / ECDH** (over chunked `0x0016/0x0017`) |

## Per-gate results — **7/7 PASS**
| Gate | Result | Captured headline line |
|---|---|---|
| 0 Discovery | ✅ PASS | `GATE0: PASS — fee0, fee1, 180d, 180f all present` |
| 1 Auth | ✅ PASS | `GATE1: PASS — authenticated` (sign-key/ECDH) |
| 2 Battery | ✅ PASS | `GATE2: PASS — battery 42% via fee0/0x0006 byte[1]` |
| 3 HR CCCD | ✅ PASS | `GATE3: attempt-1 (no bond) — CCCD enabled OK` (no WRITE_NOT_PERMITTED) |
| 4 Parsed BPM | ✅ PASS | `GATE4: PASS — parsed BPM=68 (plausible 40..180)` |
| 5 Keep-alive | ✅ PASS | `GATE5: PASS — HR sustained past 60s with a 12s keep-alive` |
| 6 Activity fetch | ✅ PASS | `GATE6: PASS — 1 samples parsed … 1/1 carry HR (byte 3)` |

**Session end:** `MB6TEST SUMMARY p=7 s=0 gates=[0:P 1:P 2:P 3:P 4:P 5:P 6:P] fw=unknown`

## Key answers
| Question | Answer |
|---|---|
| Did `0x2A37` CCCD enable succeed? | **Yes** — once fully (sign-key) authed. Bonding/sequencing were red herrings. |
| Keep-alive interval that sustained HR past 60 s? | **12 s** (events 0-30s=12, 30-60s=12, 60-90s=9) — confirms the assumed value. |
| Battery via `fee0/0x0006`? | Yes, byte[1] = 42%. |
| Activity samples parsed? | Yes — 1 sample (recent window), HR present in byte 3. |
| Auth mechanism | Huami 2021 sign-key/ECDH; legacy AES-ECB is rejected (`0x07`) by this firmware. |

## Live-pulse evidence (varying BPM = real heart rate, not a static value)
`68, 69, 67, 68, 68, 69, 70, 71, 72, 73, 72, 71, 70, 69, 68, 67, …` bpm over ~90 s.

## Normal-use HR (not the test runner)
`HR: notifications enabled on 0x2A37.` → `HR notify: 00 49 -> 73 bpm`
(from `_onHeartRateNotified`, the real app path).

## Definition of Done — met
- Gate 4 PASS + Gate 5 PASS ✅ (real BPM, sustained 90 s).
- Keep-alive (12 s) wired into the normal HR path ✅.
- Fix lands in the real app HR path, verified by a normal-use logcat ✅.
