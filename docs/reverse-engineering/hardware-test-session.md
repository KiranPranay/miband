# Hardware Test Session — Mi Band 6

A single, ordered, halt-on-fail run that confirms each protocol claim in
[protocol-mb6.md](protocol-mb6.md) against the **physical band**. It is the
hardware counterpart to [verification-checklist.md](verification-checklist.md).

## How to run
1. **Wear the band snugly** on your wrist (skin contact; wear-detection active).
   HR gates need a live pulse — off-wrist the band reports `0`/`255`.
2. Launch the app and let it **connect + authenticate** (wait for
   `Authentication SUCCESS!` / the band status to show authenticated).
3. Go to **Settings → Developer → "Run Hardware Test"**. It opens the **Debug
   Console** and starts streaming `MB6TEST …` lines.
4. Let it run to `MB6TEST SESSION END`. Gate 5 alone holds ~90 s (up to ~4 min if
   it has to probe all three keep-alive intervals), so the whole run can take a few
   minutes. Keep the band on your wrist the entire time.
5. Copy the log (Debug Console) and grep `MB6TEST` to read results, then fill in
   `test-results-NN.md`.

> Greppable: every headline is `MB6TEST GATEn: PASS|FAIL — …`, framed by
> `MB6TEST SESSION START` / `MB6TEST SESSION END — p/7 passed, s skipped [map]`.
> The map uses `P`=pass, `F`=fail, `S`=skipped, e.g. `[0:P 1:P 2:P 3:P 4:P 5:P 6:P]`.

## The gates

| Gate | Precondition | Action | Watch for (greppable) | Result |
|---|---|---|---|---|
| **0 Discovery** | Connected | Discover services | `MB6TEST GATE0: PASS — fee0, fee1, 180d, 180f all present` | ☐ |
| **1 Auth** | Gate 0 ok | Verify auth state | `MB6TEST GATE1: PASS — authenticated …` | ☐ |
| **2 Battery** | Gate 1 ok | Read `fee0/0x0006` | `MB6TEST GATE2: PASS — battery NN% via fee0/0x0006 byte[1] …` | ☐ |
| **3 HR CCCD** | band **worn** | Toggle `0x2A37` notify off→on | `MB6TEST GATE3: PASS — 0x2A37 CCCD enabled — no GATT_WRITE_NOT_PERMITTED …` | ☐ |
| **4 Parsed BPM** | Gate 3 ok | Write `15 01 01`→`0x2A39` | `MB6TEST GATE4: PASS — parsed BPM=NN (plausible 40..180) …` | ☐ |
| **5 Keep-alive** | Gate 4 ok | Hold 90 s, ping `0x16`; auto-probe 12→8→15 s | `MB6TEST GATE5: PASS — HR sustained past 60s with a Ns keep-alive …` | ☐ |
| **6 Activity fetch** | Gate 1 ok | Fetch since last sync | `MB6TEST GATE6: PASS — K samples parsed … M carry HR (byte 3) …` | ☐ |

## Halt / skip rules (built into the runner)
- **Gate 0:** `fee0`/`fee1` missing → **HALT** (wrong device / not bonded).
  `0x180D` missing → **skip Gates 3-5**, jump straight to Gate 6 (HR then comes
  only from the activity fetch); the skip is logged.
- **Gate 1 FAIL → HALT.** Auth must already have succeeded; the session never
  re-runs the handshake. If this fails, the refactor disturbed auth — diff the auth
  path against `main`.
- **Gate 2 FAIL** (fallback `0x2A19` used or no battery) → **continue**; the
  `fee0/0x0006` claim is marked `UNCONFIRMED`.
- **Gate 3 FAIL** → dumps `0x2A37` properties + the GATT error `code`/`description`,
  marks the "post-auth sequencing" theory **REFUTED**, **skips 4-5**, runs Gate 6.
- **Gate 4 FAIL** → classifies the cause (off-wrist / parse offset / sentinel),
  **skips Gate 5**, runs Gate 6.
- **Gate 5 FAIL** → only after probing 12 s, 8 s, and 15 s keep-alive intervals.

## Reading failures
- **Gate 3 FAIL** with `code=3` ⇒ `WRITE_NOT_PERMITTED` is real on this firmware —
  the sequencing theory is wrong; capture the code and props for the next move.
- **Gate 4 FAIL** `readings=[0,0,…]` ⇒ BPM parse offset wrong (we read `data[1]`).
  `readings=[255,…]` or no events ⇒ band not measuring — re-seat it on the wrist.
- **Gate 5** PASS detail names the interval that worked. If it is **not 12 s**,
  update `protocol-mb6.md` §3 and the `startRealtimeHeartRate` timer to match.
- **Gate 6 FAIL** prints `first32:` raw hex — paste it into a `findings-NN.md` for
  re-analysis of the 8-byte layout. (Zero samples can also just mean "no new data
  since last sync" — re-check after wearing the band a while.)

## Safety / repeatability
The session is idempotent: it resets HR state on entry, always cleans up on exit
(cancels timers/subscriptions, writes `stop-continuous`), and restores normal
realtime HR if HR works. Re-run it as many times as needed.
