# Capturing hardware-test logs over adb (Pixel 9a, headless)

Exact, repeatable commands the autonomous loop uses to install, launch, trigger
the gated hardware test **with no manual taps**, and capture the `MB6TEST` log.

## Environment
```bash
export ADB=/home/pranay/Android/Sdk/platform-tools/adb
export DEVICE=55211XEBF1RB28        # Pixel 9a (adb devices)
export PKG=com.example.band
export ACT=$PKG/.MainActivity
```

## Headless trigger (no taps)
`MainActivity.kt` reads a `run_hwtest` boolean intent extra and forwards it to Dart
(`main.dart` → `band/hwtest` MethodChannel), which waits for auth then calls
`BLEManager.runHardwareTestSession()`. Two paths:
- **Hot** (app already running + authed): `am start … --ez run_hwtest true` →
  `onNewIntent` → Dart runs the test.
- **Cold** (fresh launch): the extra is stashed and drained by Dart's
  `checkLaunchTrigger` after the first frame; the test runs once auth completes.

## One iteration

### 1. Build & install
```bash
flutter build apk --debug
$ADB -s $DEVICE install -r build/app/outputs/flutter-apk/app-debug.apk
```

### 2. Cold launch + wait for auth
```bash
$ADB -s $DEVICE shell am force-stop $PKG
$ADB -s $DEVICE logcat -c
$ADB -s $DEVICE shell am start -n $ACT          # normal launch → auto-connect+auth
# poll for auth success (timeout ~60s):
for i in $(seq 1 60); do
  $ADB -s $DEVICE logcat -d | grep -q "Authentication SUCCESS" && { echo "AUTHED"; break; }
  sleep 1
done
```

### 3. Trigger the test + capture until SUMMARY
```bash
TS=$(date +%Y%m%d-%H%M%S)              # timestamp from the shell, not the app
LOG=docs/reverse-engineering/logs/run-$TS.log
$ADB -s $DEVICE logcat -c
# stream logcat to file in the background
$ADB -s $DEVICE logcat -v time > /tmp/hwtest-raw.log &
LPID=$!
# fire the hot trigger
$ADB -s $DEVICE shell am start -n $ACT --ez run_hwtest true
# wait up to ~6 min for the session to finish (gate 5 can take minutes)
for i in $(seq 1 180); do
  grep -q "MB6TEST SUMMARY" /tmp/hwtest-raw.log && break
  sleep 2
done
kill $LPID 2>/dev/null
grep "MB6TEST" /tmp/hwtest-raw.log | tee "$LOG"
```

### 4. Parse the result in one grep
```bash
grep "MB6TEST SUMMARY" "$LOG"
# e.g. MB6TEST SUMMARY p=7 s=0 gates=[0:P 1:P 2:P 3:P 4:P 5:P 6:P] fw=V1.0.7.40
```

## Notes
- `MB6TEST` lines reach logcat via Flutter's `debugPrint` → `I/flutter`. Grep the
  raw capture for `MB6TEST` (tag-agnostic).
- Logs are saved under `docs/reverse-engineering/logs/run-<timestamp>.log` and are
  git-ignored (raw device logs); findings quote the relevant lines inline.
- HR gates (3-5) require the band **worn**; a desk band reads 0 BPM.
