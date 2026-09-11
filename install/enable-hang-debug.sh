#! /usr/bin/env bash
# One-shot setup for debugging kernel hangs (suspend/resume or otherwise) on
# SteamOS. Persists everything across reboots so it only needs to be run once.
# Not xone-specific - this is generic "make hangs leave a trace" tooling.

set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo 'This script must be run as root!' >&2
	exit 1
fi

echo "Configuring persistent journald fast-sync..."
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/99-fast-sync.conf <<'EOF'
[Journal]
SyncIntervalSec=1s
EOF

echo "Configuring persistent hang/lockup/sysrq sysctls..."
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-hang-debug.conf <<'EOF'
# Task stuck in uninterruptible sleep (D state) anywhere in the kernel
kernel.hung_task_timeout_secs = 5
kernel.hung_task_panic = 0

# CPU spinning without yielding (soft lockup) / totally unresponsive to
# interrupts (hard lockup, via the already-enabled NMI watchdog)
kernel.watchdog_thresh = 5
kernel.softlockup_panic = 0

# Allow manual SysRq stack/task dumps (Alt+SysRq+<key> on a physical
# keyboard) in case the system still responds to interrupts during a hang
kernel.sysrq = 1
EOF

echo "Configuring a boot-time service for the runtime-only knobs..."
cat > /etc/systemd/system/hang-debug-runtime.service <<'EOF'
[Unit]
Description=Enable runtime-only hang debugging knobs
DefaultDependencies=no
After=sysinit.target
Before=basic.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo 1 > /sys/power/pm_debug_messages'
ExecStart=/bin/sh -c 'echo 5 > /sys/module/rcupdate/parameters/rcu_cpu_stall_timeout'

[Install]
WantedBy=sysinit.target
EOF

echo "Applying everything now (so it's active without a reboot too)..."
systemctl daemon-reload
systemctl restart systemd-journald
sysctl --system > /dev/null
systemctl enable --now hang-debug-runtime.service

echo ""
echo "Active now and will auto-apply on every future boot:"
echo "  journald SyncIntervalSec : $(grep -h SyncIntervalSec /etc/systemd/journald.conf.d/99-fast-sync.conf)"
sysctl kernel.hung_task_timeout_secs kernel.watchdog_thresh kernel.sysrq
echo "  pm_debug_messages        : $(cat /sys/power/pm_debug_messages)"
echo "  rcu_cpu_stall_timeout    : $(cat /sys/module/rcupdate/parameters/rcu_cpu_stall_timeout)"
echo ""
echo "Done. Reproduce normally - no manual heartbeat loop or per-boot sysctl commands needed anymore."
