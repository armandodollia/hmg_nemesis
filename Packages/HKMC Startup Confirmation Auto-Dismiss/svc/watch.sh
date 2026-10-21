#!/system/bin/sh
# HKMC factory transaction 82: boot-ready NEMESIS service, v4.2.
# Requires NEMESIS's "restart" mode because this is a long-running monitor.
# One Binder command per observed head-unit wake, not per Linux kernel boot.
# No boot_id de-duplication. Never assume that Binder method 82 has an inverse.

export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:$PATH
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

SERVICE=${HKMC_SERVICE_BIN:-/system/bin/service}
BOOT_ID_FILE=${HKMC_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}
DUMPSYS=${HKMC_DUMPSYS_BIN:-/system/bin/dumpsys}
STATE=${HKMC_STATE_DIR:-/data/nemesis/state/local.hkmc.factory82}
SESSION=${HKMC_SESSION_MARKER:-/data/local/tmp/hkmc.factory82.session}
FB_BLANK=${HKMC_FB_BLANK:-/sys/class/graphics/fb0/blank}
POLL=${HKMC_POLL_SECONDS:-3}
REGISTRY_CHECK_SLEEP=${HKMC_REGISTRY_CHECK_SLEEP:-0.5}
GETPROP=${HKMC_GETPROP_BIN:-/system/bin/getprop}
# In real cold-start logs, uptime ~7s was too early and ~10s worked in v4.
# A low bound prevents a Binder-ready but not yet boot-ready call.
MIN_BOOT_UPTIME=${HKMC_MIN_BOOT_UPTIME:-10}
BOOT_READY_WAIT_SECONDS=${HKMC_BOOT_READY_WAIT_SECONDS:-3}
RETRY_READY_WAIT_SECONDS=${HKMC_RETRY_READY_WAIT_SECONDS:-30}
GAP_SECONDS=45
COOLDOWN_SECONDS=${HKMC_COOLDOWN_SECONDS:-15}

log() { echo "factory82: $(date 2>/dev/null) $*"; }

# On the first loop a direct framebuffer "on" reading can avoid a slow
# dumpsys power invocation. If not definitively on, use the known-good v4
# policy-based display check. An opt-in aggressive mode may skip that fallback.
fast_start_mode() {
    MODE=1
    if [ -r "$STATE/fast_start_mode" ]; then
        read -r SETTING < "$STATE/fast_start_mode"
        case "$SETTING" in 0|1|2) MODE=$SETTING ;; esac
    fi
    echo "$MODE"
}

read_fast_start_display_state() {
    if [ -r "$FB_BLANK" ]; then
        BLANK=$(cat "$FB_BLANK" 2>/dev/null)
        if [ "$BLANK" = 0 ]; then
            echo on
            return
        fi
    fi
    # Mode 2 is experimental: if the framebuffer didn't say "on", allow
    # Binder registration alone to trigger the startup call. This can be too
    # early on some firmware, so mode 1 is the default.
    if [ "$FAST_MODE" = 2 ]; then
        echo unknown
    else
        read_display_state
    fi
}

# Returned values: on, off, unknown. Prefer actual display policy over general
# Android wakefulness (the CPU can be awake while the panel is dark).
read_display_state() {
    if [ -x "$DUMPSYS" ]; then
        POWER=$($DUMPSYS power 2>/dev/null)
        case "$POWER" in
            *'mDisplayPowerRequest=policy=OFF'*|*'mDisplayPowerRequest=policy=0'*) echo off; return ;;
            *'mDisplayPowerRequest=policy=BRIGHT'*|*'mDisplayPowerRequest=policy=DIM'*) echo on; return ;;
            *'mScreenOn=false'*|*'mInteractive=false'*|*'mWakefulness=Asleep'*|*'mWakefulness=Dozing'*) echo off; return ;;
            *'mScreenOn=true'*|*'mInteractive=true'*|*'mWakefulness=Awake'*) echo on; return ;;
        esac
    fi
    # Head units vary: older kernels can expose the display's blank state here.
    if [ -r "$FB_BLANK" ]; then
        BLANK=$(cat "$FB_BLANK" 2>/dev/null)
        case "$BLANK" in
            0) echo on; return ;;
            1|2|3|4) echo off; return ;;
        esac
    fi
    echo unknown
}

boot_completed() {
    [ -x "$GETPROP" ] || return 1
    [ "$("$GETPROP" sys.boot_completed 2>/dev/null)" = 1 ]
}

# The binder was present at uptime=7 in the failing log, but Android had not
# completed the framework boot and the transaction returned an exception.
# Wait to at least the successful v4 startup window; avoid unbounded waits.
wait_for_min_uptime() {
    case "$MIN_BOOT_UPTIME" in ''|*[!0-9]*) return ;; esac
    while :; do
        BOOT_UP=$(uptime_seconds)
        [ "$BOOT_UP" -ge "$MIN_BOOT_UPTIME" ] && return
        sleep "$REGISTRY_CHECK_SLEEP"
    done
}

# 0: no extra attempt at sys.boot_completed; 1: confirmed ready.
# If the automotive build never exposes this property, fall back to the
# proven v4 grace period + minimum uptime rather than hang forever.
wait_for_boot_ready() {
    if boot_completed; then
        log 'sys.boot_completed=1 (framework ready)'
        return 0
    fi
    TICK=0
    # Keep this short: late readiness should not add a long delay to the nag screen.
    while [ "$TICK" -lt "$BOOT_READY_WAIT_SECONDS" ]; do
        sleep 1
        if boot_completed; then
            log "sys.boot_completed=1 after ${TICK}s of extra wait"
            return 0
        fi
        TICK=$((TICK + 1))
    done
    log "sys.boot_completed not confirmed after ${TICK}s; using v4-style timing fallback"
    return 1
}

uptime_seconds() {
    UP=0
    if [ -r /proc/uptime ]; then
        read -r UP UNUSED < /proc/uptime
    fi
    UP=${UP%%.*}
    case "$UP" in ''|*[!0-9]*) UP=0 ;; esac
    echo "$UP"
}

# A missing session marker is a helpful second wake signal on Gen5W QuickBoot,
# which clears /data/local/tmp. The service also works when this marker signal
# isn't available, using screen on/off transitions or service process restart.
write_session_marker() {
    PARENT=${SESSION%/*}
    if [ -d "$PARENT" ] && ( echo "$(uptime_seconds) $BOOT_ID" > "$SESSION" ) 2>/dev/null; then
        SESSION_WATCH=1
    else
        # Avoid a tight loop repeatedly issuing Binder calls when /data/local/tmp
        # is unavailable, unwritable, or has been removed altogether.
        SESSION_WATCH=0
        log 'temporary session marker unavailable; quickboot-marker trigger disabled'
    fi
}

apply_once() {
    WHY=$1
    NOW=$(uptime_seconds)
    if [ "$NOW" -gt 0 ] && [ "$LAST_ATTEMPT" -gt 0 ]; then
        ELAPSED=$((NOW - LAST_ATTEMPT))
        if [ "$ELAPSED" -ge 0 ] && [ "$ELAPSED" -lt "$COOLDOWN_SECONDS" ]; then
            log "coalesced wake ($WHY; $ELAPSED sec since last attempt)"
            write_session_marker
            return
        fi
    fi
    LAST_ATTEMPT=$NOW
    log "wake detected: $WHY; display=$DISPLAY_STATE; uptime=$NOW; boot_id=$BOOT_ID"
    if [ ! -x "$SERVICE" ]; then
        log "service executable missing: $SERVICE (not calling)"
        write_session_marker
        return
    fi
    # NEMESIS may start before the factory Binder service registers.
    WAIT=0
    while [ "$WAIT" -lt 240 ]; do
        REGISTRY=$($SERVICE check com.hkmc.factory 2>&1)
        case "$REGISTRY" in
            *'com.hkmc.factory: found'*) break ;;
        esac
        WAIT=$((WAIT + 1))
        sleep "$REGISTRY_CHECK_SLEEP"
    done
    if [ "$WAIT" -ge 240 ]; then
        log "factory Binder service unavailable after approximately 120 sec; $REGISTRY"
        write_session_marker
        return
    fi

    # Restore the proven v4 default grace; do not depend solely on Binder
    # service registration (the service can be callable before BOOT_COMPLETED).
    DELAY=2
    if [ -r "$STATE/wake_delay_seconds" ]; then
        read -r CONFIG_DELAY < "$STATE/wake_delay_seconds"
        case "$CONFIG_DELAY" in
            ''|*[!0-9]*) ;;
            *) if [ "$CONFIG_DELAY" -le 15 ]; then DELAY=$CONFIG_DELAY; fi ;;
        esac
    fi
    log "factory Binder registered after ${WAIT} check intervals; grace=${DELAY}s; uptime=$(uptime_seconds)"
    if [ "$DELAY" -gt 0 ]; then sleep "$DELAY"; fi
    wait_for_min_uptime
    # Even if a user previously set delay=0, don't issue on a cold boot while
    # Android explicitly reports not completed. A bounded wait is used because
    # some automotive builds may never populate the standard Android property.
    wait_for_boot_ready || :

    CALL_UPTIME=$(uptime_seconds)
    # This is just diagnostic output; not proof of UI readiness.
    BOOT_PROP=$($GETPROP sys.boot_completed 2>/dev/null)
    log "issuing: service call com.hkmc.factory 82; uptime=$CALL_UPTIME; sys.boot_completed=${BOOT_PROP:-unset}"
    RESPONSE=$($SERVICE call com.hkmc.factory 82 2>&1)
    RC=$?
    log "Binder tool exit status=$RC"
    log "Binder response: $RESPONSE"

    # Android's 'service' CLI can return exit code 0 even when the Parcel
    # contains an exception. The particular signature below is the observed
    # IllegalStateException('Cannot broadcast before boot completed').
    # Do NOT retry on an unknown response: transaction 82 is undocumented.
    RESULT=unverified
    case "$RESPONSE" in
        *'fffffffb 00000026 00610043'*|*'Cannot broadcast before boot completed'*) RESULT=boot-incomplete ;;
        *'Parcel(00000000'*) if [ "$RC" -eq 0 ]; then RESULT=parcel-zero; fi ;;
    esac

    if [ "$RESULT" = boot-incomplete ]; then
        log 'Binder returned pre-BOOT_COMPLETED exception despite CLI exit status; waiting for Android before ONE retry'
        RETRY_WAIT=0
        while [ "$RETRY_WAIT" -lt "$RETRY_READY_WAIT_SECONDS" ]; do
            if boot_completed; then break; fi
            sleep 1
            RETRY_WAIT=$((RETRY_WAIT + 1))
        done
        if boot_completed; then
            sleep 1  # allow BOOT_COMPLETED listeners to initialize
            log "retrying transaction 82 once after sys.boot_completed=1; uptime=$(uptime_seconds)"
            RESPONSE=$($SERVICE call com.hkmc.factory 82 2>&1)
            RC=$?
            log "retry Binder tool exit status=$RC"
            log "retry Binder response: $RESPONSE"
            RESULT=unverified
            case "$RESPONSE" in
                *'fffffffb 00000026 00610043'*|*'Cannot broadcast before boot completed'*) RESULT=boot-incomplete ;;
                *'Parcel(00000000'*) if [ "$RC" -eq 0 ]; then RESULT=parcel-zero; fi ;;
            esac
        else
            log "sys.boot_completed did not become 1 within ${RETRY_READY_WAIT_SECONDS}s; no blind retry"
        fi
    fi
    log "transaction outcome=$RESULT (Parcel zero is not proof the screen changed)"
    {
        echo "reason=$WHY"
        echo "date=$(date 2>/dev/null)"
        echo "boot_id=$BOOT_ID"
        echo "trigger_uptime=$NOW"
        echo "call_uptime=$CALL_UPTIME"
        echo "display=$DISPLAY_STATE"
        echo "tool_exit=$RC"
        echo "outcome=$RESULT"
        echo "response=$RESPONSE"
    } > "$STATE/last_attempt.txt"
    chmod 600 "$STATE/last_attempt.txt" 2>/dev/null
    # Even a nonzero tool status might have partially changed remote state;
    # never auto-repeat an undocumented transaction within the same wake.
    write_session_marker
}

mkdir -p "$STATE" || { log 'cannot create state directory; aborting'; exit 1; }
chmod 700 "$STATE" 2>/dev/null
BOOT_ID=unknown
if [ -r "$BOOT_ID_FILE" ]; then
    BOOT_ID=$(cat "$BOOT_ID_FILE" 2>/dev/null)
fi
LAST_ATTEMPT=0
SESSION_WATCH=1
LAST_SEEN_UPTIME=0
LAST_DISPLAY=unknown
INITIAL=1
DISPLAY_STATE=unknown
log "wake monitor v4.2 boot-ready started; boot_id=$BOOT_ID; session=$SESSION"
log "mode=restart; polling ${POLL}s; minimum cold uptime ${MIN_BOOT_UPTIME}s; boot-readiness gate; default fast startup mode 1"

while :; do
    # A screen-on framebuffer may bypass slow dumpsys on the first pass.
    # Normal mode falls back to v4 state detection when necessary; later
    # iterations always use v4 policy-based screen-wake detection.
    if [ "$INITIAL" -eq 1 ]; then
        FAST_MODE=$(fast_start_mode)
        if [ "$FAST_MODE" = 0 ]; then
            DISPLAY_STATE=$(read_display_state)
        else
            DISPLAY_STATE=$(read_fast_start_display_state)
        fi
        log "first-pass display state=$DISPLAY_STATE; fast_mode=$FAST_MODE"
    else
        DISPLAY_STATE=$(read_display_state)
    fi
    NOW=$(uptime_seconds)
    if [ "$DISPLAY_STATE" != "$LAST_DISPLAY" ]; then
        log "display state: $LAST_DISPLAY -> $DISPLAY_STATE"
    fi

    REASON=''
    # Never equate a marker's existence with "already ran this boot". This
    # was the v3 bug: an old marker survived a full cold boot and suppressed
    # the only startup trigger. The marker records "<uptime> <kernel boot_id>".
    # Compare its boot_id to this boot's UUID instead of just testing -f.
    # An off display still defers execution until the next display wake.
    if [ "$INITIAL" -eq 1 ]; then
        SESSION_BOOT_ID=''
        if [ -f "$SESSION" ]; then
            read -r SESSION_UPTIME SESSION_BOOT_ID < "$SESSION" || :
            log "startup marker present: marker_boot_id=${SESSION_BOOT_ID:-empty}; current_boot_id=$BOOT_ID"
        else
            log 'startup marker absent'
        fi
        if [ "$DISPLAY_STATE" != off ]; then
            if [ ! -f "$SESSION" ]; then
                REASON=service-start-no-marker
            elif [ -z "$SESSION_BOOT_ID" ]; then
                REASON=service-start-invalid-marker
            elif [ "$BOOT_ID" != unknown ] && [ "$SESSION_BOOT_ID" != "$BOOT_ID" ]; then
                REASON=new-kernel-boot
            else
                log 'startup marker already corresponds to current kernel boot; waiting for wake signal'
            fi
        else
            log 'display is off on service start; deferring until display is active'
        fi
        INITIAL=0
    else
        if [ "$DISPLAY_STATE" = on ] && [ "$LAST_DISPLAY" = off ]; then
            REASON=display-wake
        elif [ "$SESSION_WATCH" -eq 1 ] && [ ! -f "$SESSION" ] && [ "$DISPLAY_STATE" != off ]; then
            REASON=quickboot-temp-cleared
        elif [ "$NOW" -gt 0 ] && [ "$LAST_SEEN_UPTIME" -gt 0 ] && [ "$DISPLAY_STATE" != off ]; then
            GAP=$((NOW - LAST_SEEN_UPTIME))
            if [ "$GAP" -ge "$GAP_SECONDS" ]; then
                REASON="resume-gap-${GAP}s"
            fi
        fi
    fi

    if [ -n "$REASON" ]; then
        apply_once "$REASON"
        # Don't treat time spent waiting for Binder as a suspend/resume gap.
        NOW=$(uptime_seconds)
    fi
    LAST_DISPLAY=$DISPLAY_STATE
    LAST_SEEN_UPTIME=$NOW
    sleep "$POLL"
done
