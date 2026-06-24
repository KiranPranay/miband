# Findings 03 — Hardware test-session instrumentation

**Date:** 2026-06-24
**Iteration goal:** Make the MB6 protocol fixes verifiable on the physical band in
a single, ordered, halt-on-fail session, with one unmistakable greppable signal
per gate, and an empirical resolution for the two weakly-sourced claims (the
`0x2A37` CCCD `WRITE_NOT_PERMITTED` cause and the single-sourced 12 s keep-alive).
**No protocol opcodes change in this iteration** — this is pure instrumentation.

---

## 1. What I added (and why)

### A gated runner — `lib/core/hardware_test_session.dart`
A `part of 'ble_manager.dart'` file holding `extension HardwareTestSession on
BLEManager`. A part-file extension keeps the ~330-line harness out of the already
large `ble_manager.dart` while still reaching the private chars/state it must drive
(extensions in the same library can access private members). It adds **no protocol
bytes** beyond re-issuing the existing HR opcodes; it only *sequences and
instruments* them.

`runHardwareTestSession()` runs gates **0→6 in order and halts on a hard failure**,
so a broken upstream never lets a downstream gate spew garbage over the
connection. Each gate emits exactly one greppable headline:

```
MB6TEST GATEn: PASS — <detail>
MB6TEST GATEn: FAIL — <detail>
```

bracketed by `MB6TEST SESSION START` / `MB6TEST SESSION END — p/7 passed, s skipped
[0:P 1:P 2:P 3:P 4:P 5:P 6:P]`. Grep a log dump for `MB6TEST` to read the whole run.

| Gate | What it does | Pass signal | On fail |
|---|---|---|---|
| 0 Discovery | discover services | `fee0,fee1,180d,180f` present | fee0/fee1 missing → **halt**; 180d missing → **skip 3-5**, jump to 6 |
| 1 Auth | assert `authState==authenticated` (does **not** re-run the handshake — guardrail) | authenticated, no 0xFF | **halt** |
| 2 Battery | read `fee0/0x0006`, level=byte[1] | sane 0–100 from `0x0006` | fallback `0x2A19` used → mark `fee0/0x0006` **UNCONFIRMED**, continue |
| 3 HR CCCD | toggle `0x2A37` notify off→on (genuinely exercises the CCCD write) | enabled, no `WRITE_NOT_PERMITTED` | dump char props + GATT `code`/`description`, mark sequencing theory **REFUTED**, skip 4-5, go to 6 |
| 4 Parsed BPM | write `15 01 01`→`0x2A39`, await reading | `BPM=<40..180>` | classify: no events=off-wrist; `0`=parse offset; `255`=not measuring; skip 5 |
| 5 Keep-alive | hold 90 s pinging `0x16`; **auto-probe 12→8→15 s** | events in the 60–90 s window | record which interval sustains; none → FAIL |
| 6 Activity fetch | fetch since last sync | samples parsed, sane steps, HR at byte 3 | dump first 32 raw bytes hex |

### Capture-on-fail detail (gates 3 & 6)
- **Gate 3** logs `0x2A37`/`0x2A39` properties (read/write/notify/indicate) and, on
  exception, the `FlutterBluePlusException.code` (the Android GATT status — `3` =
  `WRITE_NOT_PERMITTED`) + `description`.
- **Gate 6** logs the first 32 accumulated payload bytes as space-separated hex
  (via the new read-only `ActivityFetcher.lastRawBuffer` getter) whenever zero
  samples parse or steps/min exceed the 1-byte max (255) — i.e. layout looks wrong.

### Gate-5 keep-alive auto-probe (the empirical bit)
The 12 s value came only from Notify. Gate 5 starts continuous HR, watches 90 s
while pinging `0x16` every 12 s, and checks for HR events in the **60–90 s window**.
If HR dies early, it re-arms continuous HR and retries with **8 s**, then **15 s**,
logging which interval sustains streaming. This turns the magic number into a
measured one instead of an assumption. (If 12 s passes first, it stops there.)

### On-wrist guard
Before gates 3-5 it logs a loud `WEAR CHECK` reminder, and Gate 4 explicitly
distinguishes *no notifications* (off-wrist) from *bpm=0* (parse offset) from
*bpm=255* (sentinel / poor fit), so an off-wrist run is surfaced rather than
silently reported as "HR returns 0".

### Trigger + visibility (least-invasive UI)
- Settings → **Developer → "Run Hardware Test"** tile (next to the existing
  "Debug Log"). It guards on connected+authenticated, fires the session, and opens
  the existing **Debug Console**, which already renders `_logger` output — so the
  `MB6TEST` banners stream live. The tile shows a running state via the new
  `BLEManager.isTestSessionRunning` getter.
- One field added to `BLEManager` (`_isTestSessionRunning`) + a private
  `_emitChange()` forwarder so the extension can refresh the UI without touching
  the `@protected` `notifyListeners`.

### Idempotency / cleanup
On entry the runner stops any auto-started realtime HR (timer + subscription); on
exit (always, via `finally`) it cancels the session subscription, writes
`stop-continuous`, and — if HR works and still connected — restores normal realtime
HR. No orphaned timers/subscriptions/foreground services. Safe to re-run.

### Test hygiene
- Added `ActivityFetcher.lastRawBuffer` (read-only) — instrumentation only.
- Replaced the stale default `test/widget_test.dart` (it referenced a non-existent
  `MyApp` counter UI and failed to compile, breaking `flutter analyze` and
  `flutter test`) with a minimal valid `BLELogger` smoke test. The MB6 parsing
  tests in `mb6_protocol_test.dart` are unchanged and still pass. **Surfacing
  this:** the old file was pre-existing template cruft, not a real test of this app.

## 2. How it differs from our code
This iteration does not change protocol behaviour. It composes existing methods
(`_writeHrControl`, `_setupHeartRate` discovery loop, `ActivityFetcher`) into a
deterministic, instrumented sequence. The only new runtime behaviour is the Gate-5
retry loop, which re-issues the **already-defined** `15 01 01` / `0x16` opcodes at
different cadences.

## 3. Hypothesis status
- `0x2A37` `WRITE_NOT_PERMITTED` cause — **still unproven; Gate 3 will decide it on
  hardware** (PASS ⇒ sequencing theory holds; FAIL+code ⇒ refuted, with the GATT
  code captured for the next move).
- 12 s keep-alive — **still single-sourced; Gate 5 measures it** (12/8/15 s probe).

## 4. Changes made this iteration
- `lib/core/hardware_test_session.dart` (new) — gated runner.
- `lib/core/ble_manager.dart` — `part` directive, `_isTestSessionRunning` +
  `isTestSessionRunning`, `_emitChange()`.
- `lib/core/activity_fetcher.dart` — `lastRawBuffer` getter.
- `lib/ui/settings_screen.dart` — "Run Hardware Test" tile + handler.
- `test/widget_test.dart` — replaced broken template with a valid smoke test.
- Docs: `hardware-test-session.md`, `test-results-01.md` (template), this file,
  `00-INDEX.md`.

## 5. Open questions / next goal
Run the session on the worn band and fill in `test-results-01.md`. The two live
questions Gates 3 and 5 will answer:
1. Does `0x2A37` CCCD enable succeed post-auth? (Gate 3)
2. What keep-alive interval actually sustains HR? (Gate 5) — if not 12 s, update
   `protocol-mb6.md` §3 and the `startRealtimeHeartRate` timer.
