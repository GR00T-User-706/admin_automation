#!/usr/bin/bash

#----------------------------------------------------------
# fail-safe logic if a command exits non-zero script stops
set -e
#----------------------------------------------------------

#----------------------------------------------------------
# VAIRABLE DEFINITION
FILENAME="weekly-maintenance.sh"
LOGFILE="/var/log/weekly-maintenance.log"
ERROR_MSG="ERROR: cannot create/write to $LOGFILE. Exiting"
ROOT_ERROR="ERROR: This script must be run as root. Exiting."
#----------------------------------------------------------

#----------------------------------------------------------
# SAFETY CHECKPOINTS where i want this to fail if it does
#----------------------------------------------------------
# CHECKPOINT 1: AM I ROOT if not fail hard sending
# the error messages to journald ans dmesg as fallback
if  [[ $EUID -ne 0 ]]; then
    logger -t "$FILENAME" "$ROOT_ERROR"
    echo "$FILENAME: $ROOT_ERROR" >/dev/kmsg
    exit 1
fi

# CHECKPOINT: Can root write to the log? if not fail but send
# the error messages to journald and dmesg as fallback
if ! touch "$LOGFILE" 2>/dev/null; then
    logger -t "$FILENAME" "$ERROR_MSG"
    echo "$FILENAME: $ERROR_MSG" >/dev/kmsg
    exit 1
fi

# Now that we know who we are establish the correct logging
# sending STDERR to the same place as STDOUT
exec > >(tee -a "$LOGFILE") 2>&1


# CHECKPOINT check to make sure pacman is not already running
if pidof pacman >/dev/null; then
    echo "ERROR: pacman is already running. Exiting."
    exit 1
fi

# Laptop Only Check: checks to make sure there is AC power, gives non-fatal warning message about running on BAT alone
if [[ -f /sys/class/power_supply/AC/online ]]; then
    if [[ $(cat /sys/class/power_supply/AC/online) -ne 1 ]]; then
        echo "WARNING: Not on AC power. Running upgrades on BAT alone will drain power, please connect to AC power."
    fi
fi

# Make sure there is a network connection
if ! ping -c1 8.8.8.8 >/dev/null 2>&1; then
    echo "ERROR: Network is unreachable. Exiting."
    exit 1
fi


echo "#==================================================================================#"
echo "# RUN START: $(date) | Host: $(hostname) | OS & KERNEL INFO BELOW"
echo "#==================================================================================#"
hostnamectl
echo "#==================================================================================#"
# Full system upgrade if pacman is the systems package manager
if  command -v pacman >/dev/null 2>&1; then
    echo "Performing full system upgrade...."
    pacman -Syyu
fi
# Remove any orphans or unused packages
orphans="$(pacman -Qtdq || true)"
if [[ -n "$orphans" ]]; then
    echo "Removing orphan packages....."
    pacman -Rns "$orphans"
else
    echo "No orphan packages to remove."
fi

# Clean package cache, "keep last 3 versions"
echo "Pruning old package cache"
paccache -r

if command -v timeshift >/dev/null 2>&1; then
    echo "Removing all old Timeshift snapshots..."
    timeshift --delete-all --yes || echo "WARNING: Timeshift cleanup failed, check manually."
else
    echo "WARNING: Timeshift not installed. Skipping snapshot cleanup."
fi

# Define warning message to be displayed to any users on the system
WARNING_MSG="# SYSTEM MAINTENANCE COMPLETE.
# SYSTEM WILL NOW PERFORM A MANDATORY REBOOT IN 5 MINUTES.
# Save your work NOW! THIS IS NOT A SUGGESTION, THIS IS FACT.
# Only way out is to accept fate and reboot manually or let it happen.
# YOU HAVE BEEN WARNED."

# warning notification to the user
wall "$WARNING_MSG"

# Footer for the Log file showing the end of the run
echo "#==================================================================================#"
echo "# RUN END $(date)"
echo "$WARNING_MSG"
echo "# shutdown -r +5 'MANDATORY SYSTEM REBOOT: Maintenance complete. Save work now.'"
echo "#==================================================================================#"
# Shedule the reboot with systemd-inhibit to add friction to prevent cancellation
systemd-inhibit --what=shutdown:sleep:idle --who="System Admin" --why="Mandatory system maintenance" --mode=block \
    shutdown -r +5 "$WARNING_MSG"
