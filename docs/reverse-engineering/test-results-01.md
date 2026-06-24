# Hardware Test Results — Run 01 (TEMPLATE)

> Fill this in **after** running the session (Settings → Developer → Run Hardware
> Test). Copy the Debug Console log, grep `MB6TEST`, and paste the actual headline
> lines below. **Never overwrite this file** — for the next run, copy it to
> `test-results-02.md` and so on.

## Run metadata
| Field | Value |
|---|---|
| Date / time | `____-__-__ __:__` |
| Tester | `____` |
| Phone + Android version | `____` |
| Band model (advertised name) | `Mi Smart Band 6 / Mi Band 6 NFC?` |
| **Band firmware version** | `____` (Mi Fit/Zepp → device → about) |
| App branch / commit | `reverse-engineer-mb6-protocol @ ______` |
| Band worn during HR gates? | ☐ yes ☐ no |

## Per-gate results
Paste the exact `MB6TEST GATEn:` headline line captured for each gate.

| Gate | Result | Captured headline line |
|---|---|---|
| 0 Discovery | ☐ PASS ☐ FAIL ☐ SKIP | `MB6TEST GATE0: …` |
| 1 Auth | ☐ PASS ☐ FAIL | `MB6TEST GATE1: …` |
| 2 Battery | ☐ PASS ☐ UNCONFIRMED ☐ FAIL | `MB6TEST GATE2: …` |
| 3 HR CCCD | ☐ PASS ☐ FAIL ☐ SKIP | `MB6TEST GATE3: …` |
| 4 Parsed BPM | ☐ PASS ☐ FAIL ☐ SKIP | `MB6TEST GATE4: …` |
| 5 Keep-alive | ☐ PASS ☐ FAIL ☐ SKIP | `MB6TEST GATE5: …` |
| 6 Activity fetch | ☐ PASS ☐ FAIL | `MB6TEST GATE6: …` |

**Session end line:** `MB6TEST SESSION END — _/7 passed, _ skipped [____]`

## Key answers (the two suspect claims)
| Question | Answer from this run |
|---|---|
| Did `0x2A37` CCCD enable succeed post-auth? | ☐ yes (sequencing theory holds) ☐ no — GATT `code=__`, desc `____` |
| Which keep-alive interval sustained HR past 60 s? | `__ s` (probed 12 → 8 → 15) |
| Battery served from `fee0/0x0006`? | ☐ yes (byte[1]=__%) ☐ no, fallback `0x2A19` |
| Activity samples parsed? | `__ samples, __ with HR>0, maxSteps/min=__` |

## Capture-on-fail dumps (only if a gate failed)
### Gate 3 (HR CCCD) — characteristic props + GATT error
```
<paste the MB6TEST GATE3 props line + the FAIL line with code/description>
```

### Gate 6 (activity) — first 32 raw bytes
```
<paste the "first32: .." hex line>
```

## Follow-up actions (decide after the run)
- [ ] Gate 3 FAIL → investigate GATT `code` (3 = WRITE_NOT_PERMITTED); record a new
      `findings-NN.md`; the "sequencing" note in `protocol-mb6.md` §3 is wrong.
- [ ] Gate 5 interval ≠ 12 s → update `protocol-mb6.md` §3 + the
      `startRealtimeHeartRate` keep-alive timer; commit separately with a
      `findings-NN.md` entry.
- [ ] Gate 6 garbage → re-analyse the 8-byte layout against the pasted raw hex.
- [ ] All green → mark the HR/battery/fetch rows ✅ in
      `diff-our-vs-correct.md` and `00-INDEX.md`.
