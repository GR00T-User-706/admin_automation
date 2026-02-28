#!/usr/bin/bash

set -e

FILENAME="weekly-maintenance_v4.sh"
LOGDIR="/var/log/weekly-maintenance"
LOGFILE="$LOGDIR/maintenance.log"
ERROR_MSG="ERROR: cannot create/write to $LOGFILE. Exiting"
ROOT_ERROR="ERROR: This script must be run as root. Exiting."

# CHECKPOINT 1: AM I ROOT
if [[ $EUID -ne 0 ]]; then
    logger -t "$FILENAME" "$ROOT_ERROR"
    echo "$FILENAME: $ROOT_ERROR" >/dev/kmsg
    exit 1
fi

# CHECKPOINT 2: Create log directory and ensure it's writable
if ! mkdir -p "$LOGDIR" 2>/dev/null || ! touch "$LOGFILE" 2>/dev/null; then
    logger -t "$FILENAME" "$ERROR_MSG"
    echo "$FILENAME: $ERROR_MSG" >/dev/kmsg
    exit 1
fi

# Function to close logging and sync before reboot
cleanup_and_shutdown() {
    exec >&-
    exec 2>&-
    sleep 1
    sync
    
    # Use & to background the shutdown so the inhibitor can release
    systemd-inhibit --what=shutdown:sleep:idle --who="System Admin" --why="Mandatory maintenance" --mode=block \
        shutdown -r +5 "Maintenance complete. Rebooting in 5 minutes." &
    
    wait
}

trap cleanup_and_shutdown EXIT

# NOW redirect ONLY to file, NOT to stdout (no tee duplication)
exec >> "$LOGFILE" 2>&1

# CHECKPOINT 3: Check pacman not running
if pidof pacman >/dev/null; then
    echo "ERROR: pacman is already running. Exiting."
    exit 1
fi

# CHECKPOINT 4: Network check (with retries)
echo "Checking network connectivity..."
for i in {1..5}; do
    if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then
        break
    fi
    if [[ $i -lt 5 ]]; then
        echo "Network not ready, waiting... (attempt $i/5)"
        sleep 2
    else
        echo "ERROR: Network is unreachable after 5 attempts. Exiting."
        exit 1
    fi
done

# Check AC power (non-fatal)
if [[ -f /sys/class/power_supply/AC/online ]]; then
    if [[ $(cat /sys/class/power_supply/AC/online) -ne 1 ]]; then
        echo "WARNING: Not on AC power. Running upgrades on battery will drain power."
    fi
fi

echo "#==================================================================================#"
echo "# RUN START: $(date '+%Y-%m-%d %H:%M:%S') | Host: $(hostname) | OS & KERNEL INFO"
echo "#==================================================================================#"
echo "# $(hostnamectl) #"
echo "#==================================================================================#"

# Full system upgrade
if command -v pacman >/dev/null 2>&1; then
    echo "Performing full system upgrade...."
    pacman -Syyu --noconfirm --needed || echo "WARNING: pacman upgrade had issues, continuing..."
fi

# Remove orphans
orphans="$(pacman -Qtdq || true)"
if [[ -n "$orphans" ]]; then
    echo "Removing orphan packages....."
    pacman -Rns ${orphans[*]} --noconfirm || echo "WARNING: Failed to remove some orphans"
else
    echo "No orphan packages to remove."
fi

# Clean package cache - install pacman-contrib if missing
if ! command -v paccache >/dev/null 2>&1; then
    echo "Installing pacman-contrib for paccache..."
    pacman -S pacman-contrib --noconfirm
fi

echo "Pruning old package cache"
paccache -r --keep 3 || echo "WARNING: paccache cleanup had issues"

# Timeshift cleanup
if command -v timeshift >/dev/null 2>&1; then
    echo "Removing all old Timeshift snapshots..."
    timeshift --delete-all --yes 2>/dev/null || echo "WARNING: Timeshift cleanup failed"
else
    echo "WARNING: Timeshift not installed. Skipping snapshot cleanup."
fi

WARNING_MSG="SYSTEM MAINTENANCE COMPLETE. SYSTEM WILL REBOOT IN 5 MINUTES. Save work NOW"

wall "$WARNING_MSG"

echo "#==================================================================================#"
echo "# RUN END: $(date +%c)"

echo "# $WARNING_MSG"
echo "#==================================================================================#"

# Flush all buffers to disk before reboot
sync
