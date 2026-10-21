#!/system/bin/sh
# NEMESIS stops the registered monitor before running preuninstall.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
rm -f /data/local/tmp/hkmc.factory82.session
rm -f /data/nemesis/state/local.hkmc.factory82.last_boot
rm -f /data/nemesis/state/local.hkmc.factory82.applied
# Leave earlier getprop snapshots and v3 attempt record in place for diagnosis.
echo 'factory82: wake monitor removed; automatic calls stopped'
echo 'factory82: no inverse Binder command issued (transaction 82 undocumented)'
exit 0
