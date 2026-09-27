#!/bin/bash

set -euo pipefail

CONFIG="${MONITOR_CONFIG:-/etc/cloudlinux-monitor.conf}"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config not found: $CONFIG"
    exit 1
fi

source "$CONFIG"

BASE="${BASE:?BASE is not set}"
THRESHOLD="${THRESHOLD:-80}"
RETENTION_DAYS="${RETENTION_DAYS:-90}"

WHMAPI="${WHMAPI:-/usr/local/cpanel/bin/whmapi1}"
JQ="${JQ:-/usr/bin/jq}"

DATA_DIR="$BASE/data"
REPORT_DIR="$BASE/reports"

DATE="$(date +%F)"
NOW="$(date '+%F %T')"

JSON_FILE="$DATA_DIR/disk-$DATE.json"
TMP_JSON="$DATA_DIR/.disk-$DATE.tmp.json"

HTML_FILE="$REPORT_DIR/report-disk-$DATE.html"
TMP_HTML="$REPORT_DIR/.report-disk-$DATE.tmp.html"

mkdir -p "$DATA_DIR" "$REPORT_DIR"

echo "[$NOW] Collecting cPanel disk usage..."

if [ ! -x "$WHMAPI" ]; then
    echo "ERROR: whmapi1 not found or not executable: $WHMAPI"
    exit 1
fi

if [ ! -x "$JQ" ]; then
    echo "ERROR: jq not found or not executable: $JQ"
    exit 1
fi

cleanup() {
    rm -f "$TMP_JSON" "$TMP_HTML"
}

trap cleanup EXIT

# Get cPanel account information
"$WHMAPI" --output=jsonpretty listaccts > "$TMP_JSON"

# Validate API JSON
"$JQ" empty "$TMP_JSON"

# Normalize disk usage data
"$JQ" \
    --arg date "$DATE" \
    --arg generated "$NOW" \
    --argjson threshold "$THRESHOLD" '

def to_mb:
  if . == null then 0
  elif endswith("K") then
    (rtrimstr("K") | tonumber) / 1024
  elif endswith("M") then
    (rtrimstr("M") | tonumber)
  elif endswith("G") then
    (rtrimstr("G") | tonumber) * 1024
  elif endswith("T") then
    (rtrimstr("T") | tonumber) * 1024 * 1024
  elif endswith("P") then
    (rtrimstr("P") | tonumber) * 1024 * 1024 * 1024
  else
    tonumber / 1048576
  end;

{
  date: $date,
  generated_at: $generated,
  threshold_percent: $threshold,

  accounts: [
    .data.acct[]
    | select(
        .disklimit != null
        and .diskused != null
        and .disklimit != "unlimited"
        and .diskused != "unlimited"
      )

    | (.diskused | to_mb) as $used_mb
    | (.disklimit | to_mb) as $limit_mb

    | {
        username: .user,
        domain: .domain,

        disk_used: .diskused,
        disk_limit: .disklimit,

        disk_used_mb:
          ($used_mb * 10 | round / 10),

        disk_limit_mb:
          ($limit_mb * 10 | round / 10),

        disk_percent:
          (
            if $limit_mb > 0
            then (($used_mb / $limit_mb) * 100 * 10 | round / 10)
            else 0
            end
          )
      }
  ]
}

| .accounts |= sort_by(-.disk_percent)

' "$TMP_JSON" > "$JSON_FILE"

# Validate generated JSON
"$JQ" empty "$JSON_FILE"

TOTAL="$(
    "$JQ" '.accounts | length' "$JSON_FILE"
)"

HIGH80="$(
    "$JQ" '[.accounts[] | select(.disk_percent >= 80)] | length' "$JSON_FILE"
)"

HIGH90="$(
    "$JQ" '[.accounts[] | select(.disk_percent >= 90)] | length' "$JSON_FILE"
)"

HIGH95="$(
    "$JQ" '[.accounts[] | select(.disk_percent >= 95)] | length' "$JSON_FILE"
)"

HIGH100="$(
    "$JQ" '[.accounts[] | select(.disk_percent >= 100)] | length' "$JSON_FILE"
)"

# Generate HTML report

{
cat <<HTML
<!DOCTYPE html>
<html lang="en">
<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>Disk Usage Report - $DATE</title>

<style>

* {
    box-sizing: border-box;
}

body {
    margin: 0;
    padding: 30px;
    font-family: Arial, sans-serif;
    background: #f4f6f8;
    color: #1f2937;
}

.container {
    max-width: 1400px;
    margin: auto;
}

h1 {
    margin-bottom: 5px;
}

.subtitle {
    color: #6b7280;
    margin-bottom: 25px;
}

.cards {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 15px;
    margin-bottom: 25px;
}

.card {
    background: white;
    padding: 20px;
    border-radius: 12px;
    box-shadow: 0 2px 8px rgba(0,0,0,.06);
}

.card .title {
    color: #6b7280;
    font-size: 14px;
}

.card .number {
    font-size: 28px;
    font-weight: bold;
    margin-top: 8px;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(0,0,0,.06);
}

th,
td {
    padding: 13px 12px;
    text-align: left;
    border-bottom: 1px solid #e5e7eb;
}

th {
    background: #111827;
    color: white;
}

tr.warning {
    background: #fffbea;
}

tr.critical {
    background: #fff4e5;
}

tr.urgent {
    background: #fff0f0;
}

tr.over {
    background: #ffe4e4;
    font-weight: bold;
}

.percent {
    font-weight: bold;
}

.badge {
    display: inline-block;
    padding: 5px 9px;
    border-radius: 6px;
    font-size: 12px;
    font-weight: bold;
}

.badge-warning {
    background: #fef3c7;
    color: #92400e;
}

.badge-critical {
    background: #fed7aa;
    color: #9a3412;
}

.badge-urgent {
    background: #fecaca;
    color: #991b1b;
}

.badge-over {
    background: #ef4444;
    color: white;
}

.empty {
    padding: 30px;
    text-align: center;
    background: white;
    border-radius: 12px;
}

@media (max-width: 900px) {

    .cards {
        grid-template-columns: repeat(2, 1fr);
    }

    body {
        padding: 15px;
    }

    table {
        font-size: 13px;
    }
}

@media (max-width: 600px) {

    .cards {
        grid-template-columns: 1fr;
    }

    table {
        display: block;
        overflow-x: auto;
        white-space: nowrap;
    }
}

</style>

</head>

<body>

<div class="container">

<h1>💾 Disk Usage Report</h1>

<div class="subtitle">
    Date: $DATE &nbsp; | &nbsp; Generated: $NOW
</div>

<div class="cards">

<div class="card">
    <div class="title">Accounts Checked</div>
    <div class="number">$TOTAL</div>
</div>

<div class="card">
    <div class="title">Disk ≥ 80%</div>
    <div class="number">$HIGH80</div>
</div>

<div class="card">
    <div class="title">Disk ≥ 90%</div>
    <div class="number">$HIGH90</div>
</div>

<div class="card">
    <div class="title">Disk ≥ 95%</div>
    <div class="number">$HIGH95</div>
</div>

<div class="card">
    <div class="title">Over Quota ≥ 100%</div>
    <div class="number">$HIGH100</div>
</div>

</div>

HTML

if [ "$HIGH80" -eq 0 ]; then

cat <<HTML
<div class="empty">
    No accounts have reached 80% disk usage.
</div>
HTML

else

cat <<HTML
<table>

<thead>

<tr>
    <th>User</th>
    <th>Domain</th>
    <th>Used</th>
    <th>Limit</th>
    <th>Usage</th>
    <th>Status</th>
</tr>

</thead>

<tbody>
HTML

"$JQ" -r --argjson threshold "$THRESHOLD" '
.accounts[]
| select(.disk_percent >= $threshold)
| [
    .username,
    .domain,
    .disk_used,
    .disk_limit,
    (.disk_percent | tostring)
  ]
| @tsv
' "$JSON_FILE" |
while IFS=$'\t' read -r USER DOMAIN USED LIMIT PERCENT; do

    PERCENT_INT="$(printf "%.0f" "$PERCENT")"

    if [ "$PERCENT_INT" -ge 100 ]; then
        ROW_CLASS="over"
        BADGE_CLASS="badge-over"
        STATUS="Over Quota"

    elif [ "$PERCENT_INT" -ge 95 ]; then
        ROW_CLASS="urgent"
        BADGE_CLASS="badge-urgent"
        STATUS="Urgent"

    elif [ "$PERCENT_INT" -ge 90 ]; then
        ROW_CLASS="critical"
        BADGE_CLASS="badge-critical"
        STATUS="Critical"

    else
        ROW_CLASS="warning"
        BADGE_CLASS="badge-warning"
        STATUS="Warning"
    fi

cat <<HTML
<tr class="$ROW_CLASS">

    <td>$USER</td>

    <td>$DOMAIN</td>

    <td>$USED</td>

    <td>$LIMIT</td>

    <td class="percent">${PERCENT}%</td>

    <td>
        <span class="badge $BADGE_CLASS">
            $STATUS
        </span>
    </td>

</tr>
HTML

done

cat <<HTML
</tbody>

</table>
HTML

fi

cat <<HTML

</div>

</body>
</html>

HTML

} > "$TMP_HTML"

mv "$TMP_HTML" "$HTML_FILE"

echo "[$NOW] JSON saved: $JSON_FILE"
echo "[$NOW] HTML saved: $HTML_FILE"
echo "[$NOW] Accounts checked: $TOTAL"
echo "[$NOW] Disk >= 80%: $HIGH80"
echo "[$NOW] Disk >= 90%: $HIGH90"
echo "[$NOW] Disk >= 95%: $HIGH95"
echo "[$NOW] Disk >= 100%: $HIGH100"
echo "[$NOW] Done."

# Retention

find "$DATA_DIR" \
    -maxdepth 1 \
    -type f \
    -name 'disk-20??-??-??.json' \
    -mtime +"$RETENTION_DAYS" \
    -delete

find "$REPORT_DIR" \
    -maxdepth 1 \
    -type f \
    -name 'report-disk-20??-??-??.html' \
    -mtime +"$RETENTION_DAYS" \
    -delete

echo "[$NOW] Disk retention cleanup completed."
