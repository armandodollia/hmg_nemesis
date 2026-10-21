# Pre-made Packages

This folder contains the NEMESIS package catalog. Some existing entries provide only USB installation descriptors, while new package contributions should include their reviewable source files.

## Contributing a package

**Provide the unpacked contents of the NEMESIS package directly in its own folder** under `Packages/<Package Name>/`. Do not commit a prebuilt ZIP as the contribution, and do not submit only a USB installer descriptor when contributing a new package. Keep relative paths exactly as they would appear at the root of the installable package archive.

For example:

```text
Packages/
  My Package/
    NEMESIS.data           # package manifest: id, name, types, services, etc.
    README.md              # what it does, compatibility, install and uninstall
    svc/daemon.sh          # if the package registers a service
    scripts/preuninstall.sh
    bin/tool.sh            # optional application
    tests/                 # optional source/tests
```

The `NEMESIS.data` in a **package source folder** is its own manifest (for example, `[nemesis] id=my.tool` and `[service.0]`). This differs from a **USB-root installer descriptor**, which uses `[nemesis] type=install` and `path=packages/my.tool.zip` to point to a ZIP on the USB drive. Existing descriptor-only entries in this catalog remain as-is.

To create an installable ZIP from the unpacked package, follow [the package builder documentation](../04-Packages.md). A USB stick can then contain that ZIP at the relative `path` specified by its USB-root installer descriptor. Use one NEMESIS installer descriptor at a time on the stick.

## Catalog

| Name | Description | Compatibility |
| ---- | ----------- | ------------- |
| Turn-by-Turn Guidance for Phone Projection | Cluster and HUD turn-by-turn guidance for Android Auto and Apple CarPlay | Kia EV6 firmware 260507 |
| Enable ADB | Clears the hide flag on ADB in Engineering Mode. After install, open Engineering Mode, Module Info, page 3, and tap a corner of the screen until the ADB menu appears | Universal. The package snapshots the live unit and reboots |
| Enable Wireless Features | Enables WiFi control and wireless phone projection. Apple CarPlay through this package is not verified | Head units with a WiFi module |
