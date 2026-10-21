#!/usr/bin/env python3
"""Performance and startup safety checks with fake Binder and display commands."""
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'svc/watch.sh'


def scenario(mode, framebuffer, slow_dumpsys, ready_after_checks, expect_fast):
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        state = root / 'state'
        state.mkdir()
        (state / 'fast_start_mode').write_text(str(mode))
        (state / 'wake_delay_seconds').write_text('0')
        count = root / 'count'; count.write_text('0')
        calls = root / 'calls'; calls.write_text('0')
        display = root / 'display'; display.write_text('on')
        boot = root / 'boot'; boot.write_text('UUID-ONE')
        fb = root / 'fb'
        if framebuffer is not None:
            fb.write_text(str(framebuffer))
        service = root / 'service'
        service.write_text(f'''#!/bin/sh
if [ "$1" = check ]; then
  c=$(cat '{count}')
  c=$((c + 1))
  echo "$c" > '{count}'
  if [ "$c" -gt {ready_after_checks} ]; then
    echo 'Service com.hkmc.factory: found'
  else
    echo 'Service com.hkmc.factory: not found'
  fi
  exit 0
fi
if [ "$1" = call ] && [ "$2" = com.hkmc.factory ] && [ "$3" = 82 ]; then
  c=$(cat '{calls}')
  echo $((c+1)) > '{calls}'
  echo 'Result: Parcel(00000000)'
  exit 0
fi
exit 1
''')
        service.chmod(0o755)
        dumpsys = root / 'dumpsys'
        dumpsys.write_text(f'''#!/bin/sh
if [ "$1" = power ]; then
  sleep {slow_dumpsys}
  echo 'mDisplayPowerRequest=policy=BRIGHT'
fi
''')
        dumpsys.chmod(0o755)
        env = {**os.environ, 'HKMC_SERVICE_BIN': str(service), 'HKMC_BOOT_ID_FILE': str(boot),
               'HKMC_DUMPSYS_BIN': str(dumpsys), 'HKMC_FB_BLANK': str(fb),
               'HKMC_STATE_DIR': str(state), 'HKMC_SESSION_MARKER': str(root / 'session'),
               'HKMC_POLL_SECONDS': '1', 'HKMC_REGISTRY_CHECK_SLEEP': '0.5', 'HKMC_MIN_BOOT_UPTIME':'0', 'HKMC_BOOT_READY_WAIT_SECONDS':'0'}
        log = root / 'log'
        start = time.monotonic()
        with log.open('wb') as fh:
            proc = subprocess.Popen(['/bin/sh', str(SCRIPT)], env=env, stdout=fh, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                elapsed = None
                limit = start + 11
                while time.monotonic() < limit:
                    if int(calls.read_text()) > 0:
                        elapsed = time.monotonic() - start
                        break
                    time.sleep(.05)
                assert elapsed is not None, f'mode={mode}: no call; log={log.read_text()}'
                if expect_fast:
                    assert elapsed < 2.6, f'mode={mode}: call took {elapsed:.2f}s; log={log.read_text()}'
                else:
                    assert elapsed >= 2.8, f'mode={mode}: slow fallback unexpectedly skipped, elapsed={elapsed:.2f}s'
                if ready_after_checks:
                    assert int(count.read_text()) > ready_after_checks, 'failed to wait for Binder registration'
                print(f'PASS mode={mode}, framebuffer={framebuffer}, binder_missing_checks={ready_after_checks}: {elapsed:.2f}s')
            finally:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=6)

# Use 0 grace only for simulated tests (real default is the proven v4 2s).
# Mode 1, display-on framebuffer => skip a 3s dumpsys query.
scenario(mode=1, framebuffer=0, slow_dumpsys=3, ready_after_checks=1, expect_fast=True)
# Mode 1, no framebuffer => preserve v4 conservative dumpsys fallback.
scenario(mode=1, framebuffer=None, slow_dumpsys=3, ready_after_checks=0, expect_fast=False)
# Mode 0 => original v4 screen probing even if framebuffer says on.
scenario(mode=0, framebuffer=0, slow_dumpsys=3, ready_after_checks=0, expect_fast=False)
# Mode 2, missing framebuffer => explicit experimental fast mode.
scenario(mode=2, framebuffer=None, slow_dumpsys=3, ready_after_checks=1, expect_fast=True)
