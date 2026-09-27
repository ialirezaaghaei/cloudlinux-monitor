#!/bin/bash

set -euo pipefail

CONFIG="/etc/cloudlinux-monitor.conf"

if [ ! -f "$CONFIG" ]; then
    echo "ERROR: Config not found: $CONFIG"
    exit 1
fi

source "$CONFIG"

DATE="$(date +%F)"
NOW="$(date '+%Y-%m-%d %H:%M:%S')"

DATA_DIR="$BASE/data"
REPORT_DIR="$BASE/reports"

JSON_FILE="$DATA_DIR/$DATE.json"
HTML_FILE="$REPORT_DIR/report-$DATE.html"

THRESHOLD="${THRESHOLD:-80}"
LIMIT="${LIMIT:-1000}"
RETENTION_DAYS="${RETENTION_DAYS:-90}"

CLOUDLINUX_STATISTICS="${CLOUDLINUX_STATISTICS:-/usr/sbin/cloudlinux-statistics}"
JQ="${JQ:-/usr/bin/jq}"

mkdir -p "$DATA_DIR" "$REPORT_DIR"

echo "[$NOW] Collecting CloudLinux statistics..."

TMP_RAW="$(mktemp "/tmp/cloudlinux-daily-raw-XXXXXX.json")"
TMP_JSON="$(mktemp "/tmp/cloudlinux-daily-json-XXXXXX.json")"
TMP_HTML="$(mktemp "$REPORT_DIR/.daily-$DATE-XXXXXX.html")"

cleanup() {
    rm -f "$TMP_RAW" "$TMP_JSON" "$TMP_HTML"
}

trap cleanup EXIT

"$CLOUDLINUX_STATISTICS" \
    --json \
    --period=24h \
    --limit="$LIMIT" \
    > "$TMP_RAW"

"$JQ" empty "$TMP_RAW"

"$JQ" \
    --arg date "$DATE" \
    --argjson threshold "$THRESHOLD" \
    '
    {
        date: $date,
        period: "24h",
        threshold_percent: $threshold,
        users: (
            .users
            | map(
                .usage.cpu.lve = ((.usage.cpu.lve // 0) | tonumber) |
                .limits.cpu.lve = ((.limits.cpu.lve // 0) | tonumber) |
                .usage.pmem.lve = ((.usage.pmem.lve // 0) | tonumber) |
                .limits.pmem.lve = ((.limits.pmem.lve // 0) | tonumber) |

                .cpu_avg = .usage.cpu.lve |
                .cpu_limit = .limits.cpu.lve |

                .cpu_percent =
                    (
                        if .limits.cpu.lve > 0
                        then (.usage.cpu.lve / .limits.cpu.lve * 100)
                        else 0
                        end
                    ) |

                .ram_avg_mb =
                    (.usage.pmem.lve / 1048576) |

                .ram_limit_mb =
                    (.limits.pmem.lve / 1048576) |

                .ram_percent =
                    (
                        if .limits.pmem.lve > 0
                        then (.usage.pmem.lve / .limits.pmem.lve * 100)
                        else 0
                        end
                    )
            )
        )
    }
    ' "$TMP_RAW" > "$TMP_JSON"

"$JQ" empty "$TMP_JSON"

mv "$TMP_JSON" "$JSON_FILE"
chmod 644 "$JSON_FILE"

echo "[$NOW] JSON saved: $JSON_FILE"

TOTAL_USERS="$(
    "$JQ" '.users | length' "$JSON_FILE"
)"

CPU_HIGH="$(
    "$JQ" \
        --argjson threshold "$THRESHOLD" \
        '[.users[] | select(.cpu_percent >= $threshold)] | length' \
        "$JSON_FILE"
)"

RAM_HIGH="$(
    "$JQ" \
        --argjson threshold "$THRESHOLD" \
        '[.users[] | select(.ram_percent >= $threshold)] | length' \
        "$JSON_FILE"
)"

BOTH_HIGH="$(
    "$JQ" \
        --argjson threshold "$THRESHOLD" \
        '[.users[]
          | select(
                (.cpu_percent >= $threshold)
                and
                (.ram_percent >= $threshold)
            )
        ] | length' \
        "$JSON_FILE"
)"

CPU_ONLY="$(
    "$JQ" \
        --argjson threshold "$THRESHOLD" \
        '[.users[]
          | select(
                (.cpu_percent >= $threshold)
                and
                (.ram_percent < $threshold)
            )
        ] | length' \
        "$JSON_FILE"
)"

RAM_ONLY="$(
    "$JQ" \
        --argjson threshold "$THRESHOLD" \
        '[.users[]
          | select(
                (.ram_percent >= $threshold)
                and
                (.cpu_percent < $threshold)
            )
        ] | length' \
        "$JSON_FILE"
)"

cat > "$TMP_HTML" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>CloudLinux Daily Report - $DATE</title>

<style>

body {
    font-family: Arial, sans-serif;
    background: #f5f7fa;
    margin: 0;
    padding: 30px;
    color: #1f2937;
}

.container {
    max-width: 1500px;
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
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 15px;
    margin-bottom: 30px;
}

.card {
    background: white;
    border-radius: 10px;
    padding: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,.06);
}

.card-title {
    font-size: 13px;
    color: #6b7280;
    margin-bottom: 8px;
}

.card-value {
    font-size: 28px;
    font-weight: bold;
}

.table-wrapper {
    background: white;
    border-radius: 10px;
    box-shadow: 0 2px 8px rgba(0,0,0,.06);
    overflow-x: auto;
}

table {
    width: 100%;
    border-collapse: collapse;
    min-width: 1150px;
}

th {
    background: #111827;
    color: white;
    padding: 12px;
    text-align: left;
    font-size: 13px;
    white-space: nowrap;
}

td {
    padding: 11px 12px;
    border-bottom: 1px solid #e5e7eb;
    font-size: 13px;
    white-space: nowrap;
}

tr:hover {
    background: #f9fafb;
}

.status-normal {
    color: #166534;
    font-weight: bold;
}

.status-cpu {
    color: #92400e;
    font-weight: bold;
}

.status-ram {
    color: #1d4ed8;
    font-weight: bold;
}

.status-both {
    color: #991b1b;
    font-weight: bold;
}

.high-cpu {
    background: #fff7ed;
}

.high-ram {
    background: #eff6ff;
}

.high-both {
    background: #fef2f2;
}

.percent {
    font-weight: bold;
}

.footer {
    margin-top: 25px;
    color: #6b7280;
    font-size: 12px;
}

</style>

</head>

<body>

<div class="container">

<h1>CloudLinux Daily Report</h1>

<div class="subtitle">
Date: $DATE
&nbsp; | &nbsp;
Period: Last 24 Hours
&nbsp; | &nbsp;
Threshold: ${THRESHOLD}%
</div>

<div class="cards">

<div class="card">
<div class="card-title">Accounts Checked</div>
<div class="card-value">$TOTAL_USERS</div>
</div>

<div class="card">
<div class="card-title">CPU ≥ ${THRESHOLD}%</div>
<div class="card-value">$CPU_HIGH</div>
</div>

<div class="card">
<div class="card-title">RAM ≥ ${THRESHOLD}%</div>
<div class="card-value">$RAM_HIGH</div>
</div>

<div class="card">
<div class="card-title">CPU + RAM High</div>
<div class="card-value">$BOTH_HIGH</div>
</div>

<div class="card">
<div class="card-title">CPU Only</div>
<div class="card-value">$CPU_ONLY</div>
</div>

<div class="card">
<div class="card-title">RAM Only</div>
<div class="card-value">$RAM_ONLY</div>
</div>

</div>

<div class="table-wrapper">

<table>

<thead>

<tr>
<th>#</th>
<th>Username</th>
<th>Domain</th>
<th>CPU Avg</th>
<th>CPU Limit</th>
<th>CPU %</th>
<th>RAM Avg</th>
<th>RAM Limit</th>
<th>RAM %</th>
<th>Status</th>
</tr>

</thead>

<tbody>
EOF

"$JQ" -r \
    --argjson threshold "$THRESHOLD" \
    '
    .users
    | sort_by(-.cpu_percent, -.ram_percent)
    | to_entries[]
    |
    [
        (.key + 1),
        (.value.username // "-"),
        (.value.domain // "-"),
        ((.value.cpu_avg // 0) | tonumber? // 0 | . * 1000 | round / 1000),
        ((.value.cpu_limit // 0) | tonumber? // 0 | . * 100 | round / 100),
        ((.value.cpu_percent // 0) * 10 | round / 10),
        ((.value.ram_avg_mb // 0) * 10 | round / 10),
        ((.value.ram_limit_mb // 0) * 10 | round / 10),
        ((.value.ram_percent // 0) * 10 | round / 10)
    ]
    | @tsv
    ' "$JSON_FILE" |
while IFS=$'\t' read -r NUMBER USERNAME DOMAIN CPU_AVG CPU_LIMIT CPU_PERCENT RAM_AVG RAM_LIMIT RAM_PERCENT
do

    STATUS="Normal"
    ROW_CLASS=""
    STATUS_CLASS="status-normal"

    CPU_HIGH_FLAG=0
    RAM_HIGH_FLAG=0

    if awk "BEGIN {exit !($CPU_PERCENT >= $THRESHOLD)}"; then
        CPU_HIGH_FLAG=1
    fi

    if awk "BEGIN {exit !($RAM_PERCENT >= $THRESHOLD)}"; then
        RAM_HIGH_FLAG=1
    fi

    if [ "$CPU_HIGH_FLAG" -eq 1 ] && [ "$RAM_HIGH_FLAG" -eq 1 ]; then

        STATUS="CPU + RAM High"
        ROW_CLASS="high-both"
        STATUS_CLASS="status-both"

    elif [ "$CPU_HIGH_FLAG" -eq 1 ]; then

        STATUS="CPU High"
        ROW_CLASS="high-cpu"
        STATUS_CLASS="status-cpu"

    elif [ "$RAM_HIGH_FLAG" -eq 1 ]; then

        STATUS="RAM High"
        ROW_CLASS="high-ram"
        STATUS_CLASS="status-ram"

    fi

    cat >> "$TMP_HTML" <<EOF
<tr class="$ROW_CLASS">
<td>$NUMBER</td>
<td>$USERNAME</td>
<td>$DOMAIN</td>
<td>$CPU_AVG</td>
<td>$CPU_LIMIT</td>
<td class="percent">$CPU_PERCENT%</td>
<td>$RAM_AVG MB</td>
<td>$RAM_LIMIT MB</td>
<td class="percent">$RAM_PERCENT%</td>
<td class="$STATUS_CLASS">$STATUS</td>
</tr>
EOF

done

cat >> "$TMP_HTML" <<EOF

</tbody>

</table>

</div>

<div class="footer">
Generated: $NOW
</div>

</div>

</body>
</html>
EOF

mv "$TMP_HTML" "$HTML_FILE"
chmod 644 "$HTML_FILE"

echo "[$NOW] HTML saved: $HTML_FILE"

find "$DATA_DIR" \
    -type f \
    -name '*.json' \
    -mtime +"$RETENTION_DAYS" \
    -delete

find "$REPORT_DIR" \
    -type f \
    -name '*.html' \
    -mtime +"$RETENTION_DAYS" \
    -delete

echo "[$NOW] Retention cleanup completed."
