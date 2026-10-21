# HKMC Factory transaction 82 — NEMESIS v4.2 (boot-ready monitor)

## What this package does

When a supported Hyundai/Kia infotainment system starts, it may display a startup confirmation/warning screen that **requires someone to tap to acknowledge it before the infotainment interface can be used**. This package is intended to **automatically dismiss that startup prompt**, eliminating the manual confirmation step. It monitors cold boots, QuickBoot restarts, and display wake-ups, then calls `service call com.hkmc.factory 82` once Android is ready. The prompt can still appear briefly before it is dismissed.

This behavior was observed with an earlier v4 package on a 2022 Kia EV6. **v4.2 has not yet been tested on the vehicle**, and results may vary by firmware. Transaction 82 is undocumented; this package is experimental and should be tested while parked.

**Package ID:** `local.hkmc.factory82` (same as v4.0 and v4.1)  
**Service:** `local.hkmc.factory82/apply` (`kind=sh`, `uid=root`, `mode=restart`).

## Why v4.1 failed

The Oct 15 cold-boot log reported Binder registration at **kernel uptime 7 s**, followed immediately by transaction 82. The `service` executable returned status **0**, but the Binder parcel contained exception code `fffffffb` and the UTF-16 message **“Cannot broadcast before boot completed”**. v4.1 erroneously counted that as a completed call and did not retry. On another cold boot, the response was `Parcel(00000000)` at uptime 7 s but the confirmation still appeared, consistent with the call preceding full infotainment UI initialization.

By comparison, v4.0 (which worked for the user) included a **2-second grace** after service registration and the call happened later in startup.

## v4.2 behavior

- Keeps the **working v4.0 cold-boot/QuickBoot/wake detection**, including the saved kernel boot-ID comparison.
- Keeps v4.1's fast **0.5 s** Binder-registration checks; does not assume Binder registration means Android boot is complete.
- Restores a default **2 s grace delay**, and on early boot waits until **kernel uptime >=10 s**. It also allows up to 3 extra seconds for `sys.boot_completed=1` before falling back to v4-style timing. These values derive from observed v4/v4.1 logs and may need adjustment for firmware variants.
- Parses the *Binder reply*, not just the shell status. If the reply contains the **specific pre-BOOT_COMPLETED exception signature**, waits up to 30 seconds for Android's boot-complete property and **retries once** when ready. Unknown replies are not retried to avoid repeat side effects from an undocumented Binder transaction.
- Retains `mode=restart` and removes the session marker on uninstall. Uninstall **does not reverse** transaction 82; its inverse isn't known.

`Parcel(00000000)` is a successful-looking Binder reply but does **not** prove the screen was dismissed. The head unit still needs to be tested while parked.

## Contributing and building from source

This folder contains the **unpacked NEMESIS package source** for inclusion in the upstream `Packages` catalog. The root `NEMESIS.data` is the **package manifest** (with `id=local.hkmc.factory82` and `[service.0]`); it is not the `type=install` USB descriptor.

To build ZIP artifacts locally, run from the repository root:

```sh
python3 "Packages/HKMC Startup Confirmation Auto-Dismiss/build.py"
```

The build script writes installable `.nemesis.zip` and USB-ready `.USB.zip` archives into the parent `Packages/` directory. These are generated outputs; **do not commit those ZIPs** as part of the source contribution. For USB installation, extract the generated USB archive to a FAT32/exFAT drive as described below.

## Install

1. Extract `hkmc.factory82.bootready-v4.2.USB.zip` to the **root** of the USB drive; it contains `NEMESIS.data` and `packages/hkmc.factory82.bootready-v4.2.nemesis.zip`.
2. Insert the USB into the **parked** vehicle and approve install/update.
3. NEMESIS uses the same package ID, so an existing v4.1 installation can be replaced. The source repository documents this update flow: <https://github.com/xwtk/hmg_nemesis/blob/main/04-Packages.md>.
4. After a genuine cold boot / parked vehicle-off test, inspect:

```sh
nemesis service status local.hkmc.factory82/apply
nemesis log service local.hkmc.factory82/apply
```

Look for `wake monitor v4.2`, `factory Binder registered`, `sys.boot_completed=1` (if provided by the head unit), `issuing: service call`, and `transaction outcome=parcel-zero`. A pre-BOOT_COMPLETED exception will be logged explicitly and a *single* retry may follow.

## Settings

The setting directory is `/data/nemesis/state/local.hkmc.factory82`.

Use the validated **2-second** grace (recommended), even if v4.1 previously saved `wake_delay_seconds=0`:

```sh
nemesis root -c 'echo 2 > /data/nemesis/state/local.hkmc.factory82/wake_delay_seconds'
```

For the most faithful v4.0 display detection, disable the framebuffer-first shortcut (read on next service start):

```sh
nemesis root -c 'echo 0 > /data/nemesis/state/local.hkmc.factory82/fast_start_mode'
```

For v4.2 defaults, you can remove these overrides; only try tuning after establishing reliable cold-boot behavior:

```sh
nemesis root -c 'rm -f /data/nemesis/state/local.hkmc.factory82/wake_delay_seconds /data/nemesis/state/local.hkmc.factory82/fast_start_mode'
```

The minimum cold-boot uptime and boot-ready wait can be overridden with environment variables for development simulations, but NEMESIS does not set those variables from the UI. Don't lower the uptime threshold on a vehicle until you have verified the service and UI timing.

## Diagnostics and rollback

`nemesis pkg-launch local.hkmc.factory82` runs the read-only diagnostic script; with a writable USB present it saves the service log, selected state, `dumpsys`, and properties. These may contain private information.

`nemesis uninstall local.hkmc.factory82` stops future automatic calls. Transaction 82 is not reversed automatically.

**No physical head-unit testing has been performed on v4.2.** Package and local mocked service checks only. Avoid experimentation while driving.
