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
DAYS="${DAYS:-15}"

DATA_DIR="$BASE/data"
REPORT_DIR="$BASE/reports"

TODAY="$(date +%F)"

HTML_FILE="$REPORT_DIR/report-15day-$TODAY.html"
JSON_FILE="$DATA_DIR/15day-$TODAY.json"

TMP_HTML="$(mktemp "$REPORT_DIR/.15day-XXXXXX.html")"
TMP_DATA="$(mktemp "/tmp/cloudlinux-15day-XXXXXX.json")"

cleanup() {
    rm -f "$TMP_HTML" "$TMP_DATA"
}

trap cleanup EXIT

mkdir -p "$DATA_DIR" "$REPORT_DIR"

echo "[$(date '+%F %T')] Building $DAYS-day CloudLinux report..."

mapfile -t JSON_FILES < <(
    find "$DATA_DIR" \
        -maxdepth 1 \
        -type f \
        -name '20??-??-??.json' \
        -printf '%f\n' |
    sort -r |
    head -n "$DAYS"
)

AVAILABLE_DAYS="${#JSON_FILES[@]}"

if [ "$AVAILABLE_DAYS" -eq 0 ]; then
    echo "ERROR: No daily JSON files found."
    exit 1
fi

echo "[$(date '+%F %T')] Found $AVAILABLE_DAYS/$DAYS days of data."

FULL_FILES=()

for FILE in "${JSON_FILES[@]}"; do
    FULL_FILES+=("$DATA_DIR/$FILE")
done

for FILE in "${FULL_FILES[@]}"; do
    "$JQ" empty "$FILE" >/dev/null
done

"$JQ" -s \
    --argjson threshold "$THRESHOLD" '

[
    .[] as $day |
    ($day.date // "") as $date |
    $day.users[] |
    . + {report_date: $date}
]

| group_by(.username)

| map(

    . as $u |

    ($u | map(.cpu_percent)) as $cpu_values |
    ($u | map(.ram_percent)) as $ram_values |

    ($cpu_values | add / length) as $avg_cpu |
    ($ram_values | add / length) as $avg_ram |

    ($cpu_values | max) as $max_cpu |
    ($ram_values | max) as $max_ram |

    ($cpu_values |
        map(select(. >= $threshold)) |
        length
    ) as $cpu_high_days |

    ($ram_values |
        map(select(. >= $threshold)) |
        length
    ) as $ram_high_days |

    ($u | map(.faults.cpu // 0) | add) as $cpu_faults |
    ($u | map(.faults.pmem // 0) | add) as $ram_faults |

    (
        if ($avg_cpu >= $threshold or $avg_ram >= $threshold)
        then "Upgrade Candidate"

        elif ($cpu_high_days >= 5 or $ram_high_days >= 5)
        then "Review"

        elif ($cpu_high_days >= 1 or $ram_high_days >= 1)
        then "Watch"

        else "Normal"
        end
    ) as $status |

    (
        if ($avg_cpu >= $threshold and $avg_ram >= $threshold)
        then "CPU and RAM usage are consistently high. Strong upgrade candidate."

        elif ($avg_cpu >= $threshold)
        then "CPU usage is consistently high. Review for CPU/plan upgrade."

        elif ($avg_ram >= $threshold)
        then "RAM usage is consistently high. Review for memory/plan upgrade."

        elif ($cpu_high_days >= 5 and $ram_high_days >= 5)
        then "Frequent CPU and RAM peaks. Investigate workload and consider upgrade."

        elif ($cpu_high_days >= 5)
        then "Frequent CPU peaks. Investigate workload before upgrading."

        elif ($ram_high_days >= 5)
        then "Frequent RAM peaks. Investigate memory usage before upgrading."

        elif ($cpu_high_days >= 1 or $ram_high_days >= 1)
        then "Occasional resource peak. Monitor before upgrading."

        else
        "Resource usage appears normal."
        end
    ) as $recommendation |

    {
        username: ($u[0].username // "N/A"),
        domain: ($u[0].domain // "N/A"),

        days_observed: ($u | length),

        avg_cpu: $avg_cpu,
        max_cpu: $max_cpu,
        cpu_high_days: $cpu_high_days,

        avg_ram: $avg_ram,
        max_ram: $max_ram,
        ram_high_days: $ram_high_days,

        cpu_faults: $cpu_faults,
        ram_faults: $ram_faults,

        status: $status,
        recommendation: $recommendation
    }
)

| sort_by(
    if .status == "Upgrade Candidate" then 0
    elif .status == "Review" then 1
    elif .status == "Watch" then 2
    else 3
    end,
    -(.avg_cpu + .avg_ram)
)

' "${FULL_FILES[@]}" > "$TMP_DATA"

"$JQ" empty "$TMP_DATA"

mv "$TMP_DATA" "$JSON_FILE"
chmod 644 "$JSON_FILE"
TOTAL_USERS="$("$JQ" 'length' "$JSON_FILE")"

UPGRADE_COUNT="$(
    "$JQ" '[.[] | select(.status == "Upgrade Candidate")] | length' "$JSON_FILE"
)"

REVIEW_COUNT="$(
    "$JQ" '[.[] | select(.status == "Review")] | length' "$JSON_FILE"
)"

WATCH_COUNT="$(
    "$JQ" '[.[] | select(.status == "Watch")] | length' "$JSON_FILE"
)"

NORMAL_COUNT="$(
    "$JQ" '[.[] | select(.status == "Normal")] | length' "$JSON_FILE"
)"

cat > "$TMP_HTML" <<EOF
<!DOCTYPE html>
<html lang="en">

<head>

<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">

<title>CloudLinux 15-Day Resource Report</title>

<style>

body {
    font-family: Arial, sans-serif;
    margin: 30px;
    background: #f5f6f8;
    color: #222;
}

.summary {
    display: flex;
    flex-wrap: wrap;
    gap: 15px;
    margin-bottom: 25px;
}

.card {
    background: white;
    padding: 18px 25px;
    border-radius: 8px;
    box-shadow: 0 1px 5px rgba(0,0,0,.08);
    min-width: 140px;
}

.card strong {
    display: block;
    font-size: 28px;
    margin-top: 7px;
}

.upgrade {
    border-left: 5px solid #d32f2f;
}

.review {
    border-left: 5px solid #f57c00;
}

.watch {
    border-left: 5px solid #fbc02d;
}

.normal {
    border-left: 5px solid #388e3c;
}

table {
    width: 100%;
    border-collapse: collapse;
    background: white;
}

th, td {
    padding: 10px;
    border-bottom: 1px solid #eee;
    text-align: left;
}

th {
    background: #eee;
}

.upgrade-row {
    background: #fff0f0;
}

.review-row {
    background: #fff7ed;
}

.watch-row {
    background: #fffde7;
}

.status {
    font-weight: bold;
}

.status-upgrade {
    color: #c62828;
}

.status-review {
    color: #ef6c00;
}

.status-watch {
    color: #f9a825;
}

.status-normal {
    color: #2e7d32;
}

</style>

</head>

<body>

<h1>CloudLinux 15-Day Resource Report</h1>

<p>
Report date: <strong>$TODAY</strong><br>
Data available: <strong>$AVAILABLE_DAYS / $DAYS days</strong><br>
Threshold: <strong>$THRESHOLD%</strong>
</p>

<div class="summary">

<div class="card">
Accounts
<strong>$TOTAL_USERS</strong>
</div>

<div class="card upgrade">
Upgrade Candidate
<strong>$UPGRADE_COUNT</strong>
</div>

<div class="card review">
Review
<strong>$REVIEW_COUNT</strong>
</div>

<div class="card watch">
Watch
<strong>$WATCH_COUNT</strong>
</div>

<div class="card normal">
Normal
<strong>$NORMAL_COUNT</strong>
</div>

</div>

<table>

<thead>

<tr>
<th>User</th>
<th>Domain</th>
<th>Days</th>
<th>Avg CPU %</th>
<th>Max CPU %</th>
<th>CPU ≥80%</th>
<th>Avg RAM %</th>
<th>Max RAM %</th>
<th>RAM ≥80%</th>
<th>CPU Faults</th>
<th>RAM Faults</th>
<th>Status</th>
<th>Recommendation</th>
</tr>

</thead>

<tbody>
EOF

"$JQ" -r '
.[] |

(
    if .status == "Upgrade Candidate"
    then "upgrade-row"
    elif .status == "Review"
    then "review-row"
    elif .status == "Watch"
    then "watch-row"
    else ""
    end
) as $rowclass |

(
    if .status == "Upgrade Candidate"
    then "status-upgrade"
    elif .status == "Review"
    then "status-review"
    elif .status == "Watch"
    then "status-watch"
    else "status-normal"
    end
) as $statusclass |

"<tr class=\"\($rowclass)\">" +
"<td><strong>\(.username | @html)</strong></td>" +
"<td>\(.domain | @html)</td>" +
"<td>\(.days_observed)</td>" +
"<td>\(.avg_cpu | . * 10 | round / 10)%</td>" +
"<td>\(.max_cpu | . * 10 | round / 10)%</td>" +
"<td>\(.cpu_high_days) / \(.days_observed)</td>" +
"<td>\(.avg_ram | . * 10 | round / 10)%</td>" +
"<td>\(.max_ram | . * 10 | round / 10)%</td>" +
"<td>\(.ram_high_days) / \(.days_observed)</td>" +
"<td>\(.cpu_faults)</td>" +
"<td>\(.ram_faults)</td>" +
"<td class=\"status \($statusclass)\">\(.status | @html)</td>" +
"<td>\(.recommendation | @html)</td>" +
"</tr>"
' "$JSON_FILE" >> "$TMP_HTML"

cat >> "$TMP_HTML" <<EOF

</tbody>
</table>

</body>
</html>
EOF

mv "$TMP_HTML" "$HTML_FILE"
chmod 644 "$HTML_FILE"
find "$DATA_DIR" \
    -maxdepth 1 \
    -type f \
    -name '15day-20??-??-??.json' \
    -mtime +"$RETENTION_DAYS" \
    -delete

echo "[$(date '+%F %T')] JSON saved: $JSON_FILE"
echo "[$(date '+%F %T')] HTML saved: $HTML_FILE"

echo "Accounts: $TOTAL_USERS"
echo "Upgrade Candidate: $UPGRADE_COUNT"
echo "Review: $REVIEW_COUNT"
echo "Watch: $WATCH_COUNT"
echo "Normal: $NORMAL_COUNT"
echo "Data available: $AVAILABLE_DAYS/$DAYS days"
