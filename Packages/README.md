# Pre-made Packages

This folder keeps the USB stick descriptor for each catalog entry. The package source and the zip named in `NEMESIS.data` are not in this repository.

Use one NEMESIS package on the USB drive at a time. Copy `NEMESIS.data` to the stick root and the zip to the relative `path` in that descriptor (`packages/<id>.zip`).

## Catalog

| Name | Description | Compatibility |
| ---- | ----------- | ------------- |
| Turn-by-Turn Guidance for Phone Projection | Cluster and HUD turn-by-turn guidance for Android Auto and Apple CarPlay | Kia EV6 firmware 260507 |
| Enable ADB | Clears the hide flag on ADB in Engineering Mode. After install, open Engineering Mode, Module Info, page 3, and tap a corner of the screen until the ADB menu appears | Universal. The package snapshots the live unit and reboots |
| Enable Wireless Features | Enables WiFi control and wireless phone projection. Apple CarPlay through this package is not verified | Head units with a WiFi module |
| HKMC Startup Confirmation Auto-Dismiss (v4.2) | Automatically dismisses the startup confirmation/warning prompt that otherwise requires a tap before entering the infotainment interface. Detects cold boots, QuickBoot and display wake, then calls the undocumented factory Binder method after Android is ready; the prompt may appear briefly first. | Experimental Gen5W Hyundai/Kia; earlier v4 observed working on 2022 Kia EV6; v4.2 has not yet been vehicle-tested and is firmware-dependent. |
