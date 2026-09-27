#!/bin/bash

set -euo pipefail

CONFIG="/etc/cloudlinux-monitor.conf"

CRON_BEGIN="# BEGIN CLOUDLINUX-MONITOR"
CRON_END="# END CLOUDLINUX-MONITOR"

SCRIPT_DAILY="/usr/local/bin/cloudlinux-monitor-daily"
SCRIPT_DISK="/usr/local/bin/cloudlinux-monitor-disk"
SCRIPT_15DAY="/usr/local/bin/cloudlinux-monitor-15day"

DEFAULT_BASE="/var/www/html/cloudlinux-monitor"

PURGE_DATA=0

if [ "${1:-}" = "--purge-data" ]; then
    PURGE_DATA=1
elif [ $# -gt 0 ]; then
    echo "Usage:"
    echo "  $0"
    echo "  $0 --purge-data"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root."
    exit 1
fi

echo
echo "=============================================="
echo " CloudLinux Monitor - Uninstaller"
echo "=============================================="
echo

if [ "$PURGE_DATA" -eq 1 ]; then
    echo "Mode: COMPLETE REMOVAL"
    echo
    echo "WARNING:"
    echo "This will remove the CloudLinux Monitor installation"
    echo "and all collected data/reports."
else
    echo "Mode: APPLICATION REMOVAL"
    echo
    echo "Collected data and reports will be preserved."
    echo "Use --purge-data to remove them as well."
fi

echo

if [ -f "$CONFIG" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG"

    BASE="${BASE:-$DEFAULT_BASE}"
else
    BASE="$DEFAULT_BASE"
fi

case "$BASE" in
    ""|"/"|"/var"|"/var/www"|"/var/www/html")
        echo "ERROR: Unsafe BASE path: $BASE"
        exit 1
        ;;
esac

echo "Installation path:"
echo "  $BASE"
echo

if [ "$PURGE_DATA" -eq 1 ]; then
    echo "The following will be removed:"
    echo "  - Cron block"
    echo "  - Monitor scripts"
    echo "  - Configuration"
    echo "  - Dashboard"
    echo "  - Data"
    echo "  - Reports"
else
    echo "The following will be removed:"
    echo "  - Cron block"
    echo "  - Monitor scripts"
    echo "  - Configuration"
    echo "  - Dashboard"
    echo
    echo "The following will be preserved:"
    echo "  - $BASE/data"
    echo "  - $BASE/reports"
fi

echo

read -r -p "Continue with uninstall? [y/N]: " CONFIRM

case "$CONFIRM" in
    y|Y|yes|YES|Yes)
        ;;
    *)
        echo
        echo "Uninstall cancelled."
        exit 0
        ;;
esac

echo
echo "[1/4] Removing CloudLinux Monitor Cron block..."

CURRENT_CRON="$(crontab -l 2>/dev/null || true)"

if [ -n "$CURRENT_CRON" ]; then

    CLEAN_CRON="$(
        printf '%s\n' "$CURRENT_CRON" |
        awk \
            -v begin="$CRON_BEGIN" \
            -v end="$CRON_END" '
                $0 == begin {
                    inside=1
                    found=1
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

    if [ "$CLEAN_CRON" != "$CURRENT_CRON" ]; then
        printf '%s\n' "$CLEAN_CRON" | crontab -
        echo "  Cron block removed."
    else
        echo "  Cron block not found."
    fi

else
    echo "  Root crontab is empty."
fi

echo
echo "[2/4] Removing installed scripts..."

for FILE in \
    "$SCRIPT_DAILY" \
    "$SCRIPT_DISK" \
    "$SCRIPT_15DAY"
do
    if [ -e "$FILE" ]; then
        rm -f -- "$FILE"
        echo "  Removed: $FILE"
    else
        echo "  Not found: $FILE"
    fi
done

echo
echo "[3/4] Removing configuration..."

if [ -f "$CONFIG" ]; then
    rm -f -- "$CONFIG"
    echo "  Removed: $CONFIG"
else
    echo "  Configuration not found."
fi

echo
echo "[4/4] Removing web files..."

if [ -d "$BASE" ]; then

    if [ "$PURGE_DATA" -eq 1 ]; then

        rm -rf -- "$BASE"

        echo "  Removed:"
        echo "    $BASE"

    else

        if [ -f "$BASE/index.html" ]; then
            rm -f -- "$BASE/index.html"
            echo "  Removed: $BASE/index.html"
        fi

        if [ -d "$BASE" ]; then
            rmdir --ignore-fail-on-non-empty "$BASE" 2>/dev/null || true
        fi

        echo "  Data and reports preserved."

    fi

else
    echo "  Web directory not found."
fi

echo
echo "=============================================="
echo " Uninstall completed successfully."
echo "=============================================="
echo

if [ "$PURGE_DATA" -eq 0 ]; then
    echo "Collected data/reports were preserved."
    echo
    echo "To remove them later:"
    echo "  $0 --purge-data"
else
    echo "All CloudLinux Monitor data and reports were removed."
fi

echo
