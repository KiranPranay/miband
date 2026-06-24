# Findings 06 — The band requires the Huami **sign-key (ECDH) auth**, not legacy AES

**Date:** 2026-06-25
**Headline:** Driving the auth to the *correct* canonical Huami handshake revealed
the true root cause of every HR/activity failure: **this Mi Band 6 firmware
requires the Huami "sign-key" (public-key / 2021-class ECDH) authentication.** The
legacy AES-ECB auth — which all prior sessions assumed MB6 uses — is rejected by
the band with **status `0x07` = "sign key failed."** This is why the standard HR
service (`0x2A37`/`0x2A39`) and activity-data fetch are locked: our session is only
*partially* authenticated.

## How we got here (on-device, captured logs)
The earlier "auth works" was an illusion: the app authenticated on the **wrong
characteristic `fec1`**, whose non-standard 32-byte exchange our V3-fallback code
declared "success" without the band ever validating it. Switching to the canonical
auth char **`0x0009`** and replaying Gadgetbridge's `InitOperation` exactly:

| Iter | Change | Captured result |
|---|---|---|
| 3  | auth on `0x0009` | `Write error: WRITE property not supported` — `0x0009` is write-**without**-response |
| 3b | `safeWrite` picks write type | `← 10 01 81` (canonical! masked status = success) then timeout (our code only accepted `10 01 01`) |
| 4  | flags `0x08`, cryptFlags `0x80`, tolerate status high bits | full flow: `01 08 key → 10 01 81 → 82 08 02 01 00 → 10 82 01 <16 rand> → 83 08 <enc> → 10 83 07` |
| 5  | skip send-key (GB sets `needsAuth=false` for MB6 since cryptFlags≠0) | `82 08 02 01 00 → 10 82 01 <rand> → 83 08 <enc> → 10 83 07` (still `0x07`) |

So the **legacy challenge/response now runs perfectly through all three steps** —
the band returns a random, we AES-ECB-encrypt it with the auth key
(`da9bf2…8ac2`, accepted), and send it back. The band's final verdict is
**`10 83 07`**.

## What `0x07` means (decompiled Notify — the app that works with this band)
`x5/i.java` response handler (the send-encrypted-number response, `bArr[0]==0x10 &&
(bArr[1]&0x0f)==0x03`):
```java
byte b11 = bArr[2];
if (b11 == 4 || b11 == 7 || b11 == 6 || b11 == 8) {            // all failure codes
    ...
    boolean z10 = userPreferences.Ij() && bArr[2] == 8;        // 0x08 → AUTH key failed
    boolean z11 = userPreferences.Ij() && bArr[2] == 7;        // 0x07 → SIGN key failed
    ...
    if (z10) toast(R.string.pairing_authkey_failed);
    else if (z11) toast(R.string.pairing_signkey_failed);      // <-- our case
```
- **`0x07` = `pairing_signkey_failed`.** Our **auth key is accepted** (else we'd get
  `0x08`); the band is rejecting because we never performed the **sign-key** step.
- This only happens in **`Ij()` mode**, and in that mode Notify's auth `f()` does
  NOT do the legacy AES flow at all — it sends `{0x01, 0x00}` to `0x0009`
  (`x5/i.java:282-285`) to begin the **public-key / sign-key handshake**.

⇒ **This firmware uses the Huami sign-key (ECDH-class) auth.** It corresponds to
the chunked-audit finding from findings-02 (§5/§6): MB6 = `MILI_PANGU`, and on
firmware ≥ `1.0.4.1` advertising encryption capability, Notify routes it through
the **encrypted ECDH** path — exactly what `Ij()` gates. Our band is such a unit.

## Why everything else fit
- HR service `0x180D` + activity-data responses are gated behind **full** auth →
  `code=3` / no-response on a partially-authed link. Battery/steps are readable
  with partial auth, which masked the problem for prior sessions.
- `createBond()` succeeding but not helping (findings-05) is consistent: the gate
  is Huami app-layer sign-key auth, not Android bonding.

## What "sign-key auth" requires (port target: Gadgetbridge)
This is the **Huami-2021 protocol** the very first session documented in
`protocol-mb6.md` Appendix A and (incorrectly) deemed "not needed for MB6":
- `InitOperation2021` — ECDH key pair, exchange public keys, derive
  `finalSharedSessionAES = sharedEC[i+8] ^ authKey[i]`, send double-encrypted
  random, endpoint `0x0082`.
- `ECDH_B163` (the B-163 curve math), `Huami2021ChunkedEncoder` /
  `Huami2021ChunkedDecoder` over chars `0x0016`/`0x0017`, with the per-message
  `messageKey = sessionKey ^ handle`, `seqNr`, CRC32, AES.
- HR/activity/battery then ride the **encrypted chunked channel**, not the plain
  `fee0`/`0x180D` chars. (NB: Notify's `f()` starts the sign-key on `0x0009` with
  `{1,0}`; whether MB6's sign-key is fully on the chunked channel or partly on
  `0x0009` must be confirmed when implementing — both are in the references.)

All of this exists in the cloned `gadgetbridge/` tree and can be ported to Dart,
but it is a **substantial new implementation** (ECDH curve math + chunked transport
+ session-key crypto), not a one-line fix.

## Status of the success criteria
- Gate 3/4/5 (realtime HR via standard service): **not reachable on this firmware**
  — the standard HR service is permanently locked without sign-key auth. The
  task's "pivot to Gate 6" is also blocked (activity fetch needs full auth too).
- The real unlock for *both* is implementing the **sign-key/ECDH auth**.

## Decision point (surfaced to the user)
Implementing the Huami sign-key/ECDH 2021 auth is a large, well-scoped port from
Gadgetbridge. This is a scope expansion beyond "fix the HR opcode," so it needs an
explicit go-ahead. Options put to the user:
1. **Proceed** — port `ECDH_B163` + `InitOperation2021` + chunked transport to Dart,
   then run HR/activity over the encrypted channel.
2. **Stop here** with the diagnosis; optionally revert the auth char back to `fec1`
   to restore basic step/battery sync (HR remains unavailable either way).

## Code state
The canonical legacy-auth implementation (auth on `0x0009`, flags `0x08`/`0x80`,
skip-send-key, status-nibble masking) is committed as the correct foundation. It
authenticates *up to* the sign-key step; it does **not** complete auth on this
firmware, so this build does not sync until the sign-key layer is added. (Revert is
one `git` command if option 2 is chosen.)
