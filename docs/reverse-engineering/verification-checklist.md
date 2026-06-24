# Verification checklist — confirm the MB6 fixes on a real band

Run the app connected to the real Mi Band 6 and watch the logs (`_logger.i/d/e`).
Each row maps a protocol claim to the exact log line that confirms it.

## Connect + auth (should be unchanged / still working)
| # | Expectation | Log line to look for |
|---|---|---|
| 1 | Legacy auth still succeeds | `Authentication SUCCESS!` |
| 2 | `0x180D` + `fee0` services discovered | `SERVICE UUID: …180d…`, `…fee0…` |

## Realtime heart rate (the headline fix)
| # | Expectation | Log line |
|---|---|---|
| 3 | HR chars found | `HR: 0x2A37 props notify=true …` |
| 4 | `0x2A37` CCCD enable now **succeeds** (the old `WRITE_NOT_PERMITTED` is gone) | `HR: notifications enabled on 0x2A37.` (and NOT `failed to enable 0x2A37 notify`) |
| 5 | Continuous start commands written | `HR: wrote stop-manual (15 02 00) to 0x2A39.` then `HR: wrote start-continuous (15 01 01) to 0x2A39.` |
| 6 | Realtime started | `HR: realtime measurement started.` |
| 7 | **Parsed BPM arrives** | `HR notify: 00 4b -> 75 bpm` (any value 7..249) |
| 8 | Keep-alive ping fires (~every 12 s) | `HR: wrote keep-alive (16) to 0x2A39.` |
| 9 | HR continues streaming for >30 s (keep-alive working) | repeated `HR notify: … -> NN bpm` lines past the first ping |
| 10 | One-shot path (if invoked via `measureHeartRateOnce`) | `HR: wrote start-manual (15 02 01) …` → a single `HR notify:` |

> If line 4 still shows `failed to enable 0x2A37 notify … WRITE_NOT_PERMITTED`,
> HR history is still captured from the activity fetch (line 14). Next debugging
> step would then be: ensure a fresh service discovery after auth, try toggling
> notify after a longer settle, or check Android bonding state — but per Notify/GB
> this CCCD is permitted on MB6, so it should now succeed.

## Battery
| # | Expectation | Log line |
|---|---|---|
| 11 | Battery read from `fee0/0x0006`, level = byte[1] | `Battery (0x0006): 87%` (plausible value, optionally `(charging)`) |
| 12 | (fallback only if 0x0006 absent) | `Battery (0x2a19): NN%` |

## Activity / sleep / HR-history fetch
| # | Expectation | Log line |
|---|---|---|
| 13 | Fetch accepted, non-zero length | `ActivityFetcher: expected data length = <N>` (N>0) |
| 14 | 8-byte samples parsed; HR derived | `Activity fetch: got <K> samples` then `HR history: derived <M> readings from activity` |
| 15 | Steps look sane (≤255/min, monotonic-ish totals); sleep stages present overnight | inspect parsed `ActivitySample` (cat/sleep/deep/rem) in stored data |
| 16 | SpO2 fetch uses correct type | `ActivityFetcher: requesting data type 0x25 since …` |

## Sanity / regression
| # | Expectation | Log line |
|---|---|---|
| 17 | Realtime steps still work | `Steps: <n>, <m> m, <c> kcal` |
| 18 | On disconnect, keep-alive timer stops, HR state reset | `Device disconnected.` then no further `HR: wrote keep-alive` |

## Pass criteria (Definition of Done)
- Lines **4 + 7** present ⇒ realtime HR returns a parsed BPM via the standard
  `0x2A37/0x2A39` channel. ✅ core deliverable.
- Line **14** present ⇒ activity fetch returns parsed samples (incl. HR history).
- Line **11** present ⇒ battery via `fee0/0x0006`.
