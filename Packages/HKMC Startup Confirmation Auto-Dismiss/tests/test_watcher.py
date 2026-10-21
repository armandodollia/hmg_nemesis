#!/usr/bin/env python3
"""Mocked tests for NEMESIS wake watcher; never contact a vehicle."""
import os
import signal
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def eventually(test, label, seconds=9):
    end = time.monotonic() + seconds
    while time.monotonic() < end:
        if test():
            return
        time.sleep(0.12)
    raise AssertionError(label)


with tempfile.TemporaryDirectory() as d:
    t = Path(d)
    fakebin = t / 'fakebin'; fakebin.mkdir()
    display = t / 'display'; display.write_text('on')
    boot = t / 'boot_id'; boot.write_text('uuid-BOOT-A\n')
    count = t / 'call-count'; count.write_text('0')
    state = t / 'state'; state.mkdir()
    (state / 'wake_delay_seconds').write_text('0')
    session = t / 'session'
    log = t / 'service.log'

    service = fakebin / 'service'
    service.write_text(f'''#!/bin/sh
if [ "$1" = check ]; then
    echo 'Service com.hkmc.factory: found'
    exit 0
fi
if [ "$1" = call ] && [ "$2" = com.hkmc.factory ] && [ "$3" = 82 ]; then
    n=$(cat {count})
    n=$((n + 1))
    echo "$n" > {count}
    echo 'Result: Parcel(00000000 00000000)'
    exit 0
fi
exit 40
''')
    service.chmod(0o755)

    dumpsys = fakebin / 'dumpsys'
    dumpsys.write_text(f'''#!/bin/sh
if [ "$1" = power ]; then
    if [ "$(cat {display})" = off ]; then
        echo 'mDisplayPowerRequest=policy=OFF'
    else
        echo 'mDisplayPowerRequest=policy=BRIGHT'
    fi
fi
''')
    dumpsys.chmod(0o755)

    env = {**os.environ,
           'HKMC_SERVICE_BIN': str(service),
           'HKMC_DUMPSYS_BIN': str(dumpsys),
           'HKMC_BOOT_ID_FILE': str(boot),
           'HKMC_FB_BLANK': str(t / 'missing_fb'),
           'HKMC_STATE_DIR': str(state),
           'HKMC_SESSION_MARKER': str(session),
           'HKMC_POLL_SECONDS': '1',
           'HKMC_COOLDOWN_SECONDS': '1', 'HKMC_MIN_BOOT_UPTIME': '0', 'HKMC_BOOT_READY_WAIT_SECONDS': '0'}

    def calls():
        return int(count.read_text())

    proc = None

    def start():
        global proc
        proc = subprocess.Popen(['sh', str(ROOT/'svc'/'watch.sh')],
                                stdout=log.open('ab'), stderr=subprocess.STDOUT,
                                env=env, start_new_session=True)

    def stop():
        global proc
        if proc is not None:
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
            proc.wait(timeout=5)
            proc = None

    try:
        # Fresh install / boot, no marker: call once.
        start()
        eventually(lambda: calls() == 1, 'did not issue initial Binder call')
        assert 'uuid-BOOT-A' in session.read_text()
        stop()
        # Supervisor process restart within same kernel boot: don't call again.
        start()
        time.sleep(1.7)
        assert calls() == 1, 'duplicate call when monitor restarted during same boot'
        stop()
        # Regression: a genuine kernel reboot but stale marker survives.
        # Old v3 skipped this case forever when display started ON.
        boot.write_text('uuid-BOOT-B\n')
        assert session.exists(), 'reboot regression test requires surviving marker'
        display.write_text('on')
        start()
        eventually(lambda: calls() == 2, 'BUG: new kernel boot did not issue Binder call')
        assert 'uuid-BOOT-B' in session.read_text()
        eventually(lambda: 'wake detected: new-kernel-boot' in log.read_text(),
                   'new-kernel-boot trigger was not recorded')

        # Verify monitor still observes off -> on display transitions.
        display.write_text('off')
        eventually(lambda: 'display state: on -> off' in log.read_text(),
                   'display-off not detected')
        display.write_text('on')
        eventually(lambda: calls() == 3, 'display-wake did not issue Binder call')
        # The mock increments calls() before the watcher finishes writing its
        # marker. Wait for completion and the 1-second wake cooldown to avoid
        # racing that write and incorrectly coalescing the next wake.
        last_attempt = state / 'last_attempt.txt'
        eventually(lambda: last_attempt.exists()
                   and 'reason=display-wake' in last_attempt.read_text(),
                   'display-wake attempt did not finish')
        eventually(lambda: session.exists(), 'display-wake marker missing')
        time.sleep(1.2)

        # Verify QuickBoot marker-clear event while monitor runs.
        session.unlink()
        eventually(lambda: calls() == 4, 'QuickBoot marker-clear did not trigger')
        stop()

        # Boot occurs while display is still off; defer until it lights.
        boot.write_text('uuid-BOOT-C\n')
        display.write_text('off')
        start()
        time.sleep(1.6)
        assert calls() == 4, 'incorrect call while display OFF on boot'
        display.write_text('on')
        eventually(lambda: calls() == 5, 'deferred wake did not trigger')
        stop()
        print('PASS: fresh startup, same-boot process restart, stale marker across new kernel boot,')
        print('      display off/on, marker clearance, and defer-until-display-on')
        print('\nMOCK SERVICE LOG:\n' + log.read_text())
    finally:
        stop()
