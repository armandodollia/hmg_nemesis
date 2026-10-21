#!/system/bin/sh
# No Binder call. Dumps read-only wake-monitor diagnostics to USB when possible.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
STATE=/data/nemesis/state/local.hkmc.factory82
LOG=/data/nemesis/logs/local.hkmc.factory82/apply.log
SESSION=/data/local/tmp/hkmc.factory82.session

printf 'HKMC Factory 82 wake monitor v4.2 boot-ready diagnostics\n'
printf 'Current date: '; date
printf 'Current uptime: '; cat /proc/uptime 2>/dev/null
printf 'Android boot complete: '; /system/bin/getprop sys.boot_completed 2>/dev/null
printf 'Kernel boot ID: '; cat /proc/sys/kernel/random/boot_id 2>/dev/null
printf 'Temporary session marker: '
if [ -f "$SESSION" ]; then cat "$SESSION"; else echo missing; fi
if [ -f "$STATE/last_attempt.txt" ]; then cat "$STATE/last_attempt.txt"; fi

for ROOT in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1; do
    [ -d "$ROOT" ] || continue
    DEST="$ROOT/NEMESIS-factory82-diagnostics"
    mkdir -p "$DEST" 2>/dev/null || continue
    cp "$LOG" "$DEST/service.log" 2>/dev/null
    if [ -d "$STATE" ]; then
        for FILE in "$STATE"/*; do
            [ -f "$FILE" ] || continue
            cp "$FILE" "$DEST/" 2>/dev/null
        done
    fi
    /system/bin/dumpsys power > "$DEST/dumpsys-power.txt" 2>&1
    /system/bin/dumpsys display > "$DEST/dumpsys-display.txt" 2>&1
    getprop > "$DEST/getprop.txt" 2>&1
    echo "factory82: copied diagnostics to $DEST"
    echo 'factory82: diagnostics may contain private identifiers; inspect before sharing'
    exit 0
done
echo 'factory82: No writable USB found. Use nemesis log service local.hkmc.factory82/apply.'
exit 1
