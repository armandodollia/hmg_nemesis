#!/usr/bin/env python3
"""Integration simulation for the log-observed exception and once-only retry."""
import os
import pathlib
import signal
import subprocess
import tempfile
import time

root = pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as d:
    tmp = pathlib.Path(d)
    fakebin = tmp/'fakebin'; fakebin.mkdir()
    state = tmp/'state'; state.mkdir()
    (state/'wake_delay_seconds').write_text('0')
    boot_property = tmp/'boot_complete'; boot_property.write_text('0')
    calls = tmp/'calls'; calls.write_text('0')
    session = tmp/'session'
    service = fakebin/'service'
    service.write_text(f'''#!/bin/sh
if [ "$1" = check ]; then
    echo 'Service com.hkmc.factory: found'; exit 0
fi
if [ "$1" = call ]; then
    n=$(cat '{calls}'); n=$((n+1)); echo "$n" > '{calls}'
    if [ "$n" = 1 ]; then
        # Observed error signature, but `service` returns zero anyway!
        echo 'Result: Parcel('
        echo '  0x00000000: fffffffb 00000026 00610043 006e006e'
        echo '  0x00000010: 0074006f 00620020 006f0072 00640061'
        echo ')'
        echo 1 > '{boot_property}'
    else
        echo 'Result: Parcel(00000000)'
    fi
    exit 0
fi
exit 1
''')
    service.chmod(0o755)
    getprop = fakebin/'getprop'
    getprop.write_text(f'''#!/bin/sh
if [ "$1" = sys.boot_completed ]; then cat '{boot_property}'; fi
''')
    getprop.chmod(0o755)
    dumpsys = fakebin/'dumpsys'
    dumpsys.write_text("#!/bin/sh\necho 'mDisplayPowerRequest=policy=BRIGHT'\n")
    dumpsys.chmod(0o755)
    env={**os.environ,
         'HKMC_SERVICE_BIN':str(service), 'HKMC_GETPROP_BIN':str(getprop),
         'HKMC_DUMPSYS_BIN':str(dumpsys),'HKMC_BOOT_ID_FILE':str(tmp/'boot'),
         'HKMC_FB_BLANK':str(tmp/'missing_fb'),
         'HKMC_STATE_DIR':str(state),'HKMC_SESSION_MARKER':str(session),
         'HKMC_MIN_BOOT_UPTIME':'0','HKMC_BOOT_READY_WAIT_SECONDS':'0',
         'HKMC_POLL_SECONDS':'3','HKMC_RETRY_READY_WAIT_SECONDS':'4'}
    (tmp/'boot').write_text('mock-cold-boot')
    out = tmp/'output'
    with out.open('wb') as f:
        proc=subprocess.Popen(['sh',str(root/'svc/watch.sh')], stdout=f,
                              stderr=subprocess.STDOUT,env=env,start_new_session=True)
        try:
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                if calls.read_text().strip()=='2': break
                time.sleep(0.1)
            assert calls.read_text().strip()=='2', f'Expected exactly one retry, log: {out.read_text()}'
            time.sleep(.3)
            assert calls.read_text().strip()=='2', 'Unexpected extra Binder execution'
        finally:
            os.killpg(proc.pid,signal.SIGTERM)
            proc.wait(timeout=3)
    log=out.read_text()
    assert 'pre-BOOT_COMPLETED exception' in log, log
    assert 'retrying transaction 82 once' in log, log
    assert 'transaction outcome=parcel-zero' in log, log
    assert 'mock-cold-boot' in session.read_text()
    print('PASS: pre-boot Binder exception is detected despite exit code 0 and retried exactly once')
