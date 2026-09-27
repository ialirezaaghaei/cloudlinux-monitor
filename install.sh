#!/bin/bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG="/etc/cloudlinux-monitor.conf"

CRON_FILE="$REPO_DIR/cron/cloudlinux-monitor.cron"

CRON_BEGIN="# BEGIN CLOUDLINUX-MONITOR"
CRON_END="# END CLOUDLINUX-MONITOR"

echo "======================================"
echo " CloudLinux Monitor Installer"
echo "======================================"

# --------------------------------------------------
# Root check
# --------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root."
    exit 1
fi

# --------------------------------------------------
# Dependency checks
# --------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required."
    echo "Install jq and run again."
    exit 1
fi

if [ ! -x /usr/sbin/cloudlinux-statistics ]; then
    echo "ERROR: CloudLinux statistics not found:"
    echo "/usr/sbin/cloudlinux-statistics"
    exit 1
fi

if [ ! -x /usr/local/cpanel/bin/whmapi1 ]; then
    echo "ERROR: cPanel WHM API not found:"
    echo "/usr/local/cpanel/bin/whmapi1"
    exit 1
fi

# --------------------------------------------------
# Configuration
# --------------------------------------------------

if [ ! -f "$CONFIG" ]; then

    if [ ! -f "$REPO_DIR/config/monitor.conf.example" ]; then
        echo "ERROR: Configuration template not found:"
        echo "$REPO_DIR/config/monitor.conf.example"
        exit 1
    fi

    cp \
        "$REPO_DIR/config/monitor.conf.example" \
        "$CONFIG"

    chmod 600 "$CONFIG"

    echo "Created:"
    echo "$CONFIG"

else

    echo "Existing config preserved:"
    echo "$CONFIG"

fi

# --------------------------------------------------
# Load configuration
# --------------------------------------------------

source "$CONFIG"

if [ -z "${BASE:-}" ]; then
    echo "ERROR: BASE is not defined in:"
    echo "$CONFIG"
    exit 1
fi

# --------------------------------------------------
# Create directories
# --------------------------------------------------

mkdir -p \
    "$BASE/data" \
    "$BASE/reports" \
    /usr/local/bin

chmod 755 "$BASE"
chmod 755 "$BASE/data"
chmod 755 "$BASE/reports"

# --------------------------------------------------
# Install scripts
# --------------------------------------------------

install \
    -m 0755 \
    "$REPO_DIR/scripts/cloudlinux-daily.sh" \
    /usr/local/bin/cloudlinux-monitor-daily

install \
    -m 0755 \
    "$REPO_DIR/scripts/cloudlinux-15day.sh" \
    /usr/local/bin/cloudlinux-monitor-15day

install \
    -m 0755 \
    "$REPO_DIR/scripts/cpanel-disk.sh" \
    /usr/local/bin/cloudlinux-monitor-disk

# --------------------------------------------------
# Install dashboard
# --------------------------------------------------

install \
    -m 0644 \
    "$REPO_DIR/web/index.html" \
    "$BASE/index.html"

# --------------------------------------------------
# Validate cron file
# --------------------------------------------------

if [ ! -f "$CRON_FILE" ]; then
    echo "ERROR: Cron file not found:"
    echo "$CRON_FILE"
    exit 1
fi

# --------------------------------------------------
# Install / update cron jobs
#
# Existing root crontab entries are preserved.
# Only the CloudLinux Monitor block is replaced.
# --------------------------------------------------

CRON_LINES="$(cat "$CRON_FILE")"

CURRENT_CRON="$(crontab -l 2>/dev/null || true)"

CLEAN_CRON="$(
    printf '%s\n' "$CURRENT_CRON" |
    awk \
        -v begin="$CRON_BEGIN" \
        -v end="$CRON_END" '
            $0 == begin {
                inside=1
                next
            }

            $0 == end {
                inside=0
                next
            }

            !inside {
                print
            }
        '
)"

NEW_CRON="$(
    printf '%s\n' "$CLEAN_CRON"
    printf '%s\n' "$CRON_BEGIN"
    printf '%s\n' "$CRON_LINES"
    printf '%s\n' "$CRON_END"
)"

printf '%s\n' "$NEW_CRON" | crontab -

# --------------------------------------------------
# Installation summary
# --------------------------------------------------

echo
echo "Cron installed/updated successfully."
echo
echo "Cron jobs:"
echo "$CRON_LINES"

echo
echo "Installation completed."
echo
echo "Config:"
echo "  $CONFIG"
echo
echo "Dashboard:"
echo "  $BASE/index.html"
echo
echo "Installed commands:"
echo
echo "  /usr/local/bin/cloudlinux-monitor-daily"
echo "  /usr/local/bin/cloudlinux-monitor-disk"
echo "  /usr/local/bin/cloudlinux-monitor-15day"
echo
echo "Cron:"
echo
echo "  CloudLinux Monitor cron jobs installed."
echo "  Existing crontab entries were preserved."
echo
