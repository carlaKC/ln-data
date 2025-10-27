#!/bin/bash

set -e

logs_dir=${1:-"logs"}
output_file=${2:-"htlc_resolution_distribution.txt"}

if [ ! -d "$logs_dir" ]; then
    echo "Error: Logs directory not found at $logs_dir"
    echo ""
    echo "Usage: $0 [logs-directory] [output-file]"
    echo "Example: $0 logs htlc_resolution_distribution.txt"
    echo ""
    echo "Note: Please copy your LND logs into the ./logs directory first"
    exit 1
fi

echo "Processing LND logs from $logs_dir..."

temp_dir=$(mktemp -d)
combined_logs="$temp_dir/combined.log"
add_events="$temp_dir/add_events.txt"
resolve_events="$temp_dir/resolve_events.txt"

log_files=$(find "$logs_dir" -name "lnd.log*" -type f | sort -t. -k3 -rn)

echo "Found log files:"
for logfile in $log_files; do
    echo "  - $(basename $logfile)"
done
echo ""

echo "Combining log files in chronological order..."
for logfile in $log_files; do
    if [[ "$logfile" == *.gz ]]; then
        echo "Processing gzipped: $(basename $logfile)"
        gzip -cd "$logfile" || { echo "Failed to decompress $logfile"; exit 1; }
    else
        echo "Processing regular: $(basename $logfile)"
        cat "$logfile"
    fi
done > "$combined_logs"

echo "Combined log size: $(wc -l < "$combined_logs" | tr -d ' ') lines"
echo ""

echo "Extracting HTLC events..."

grep "Sending UpdateAddHTLC" "$combined_logs" | \
    sed -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+).*id=([0-9]+).*hash=([0-9a-f]+).*/\1|\2|\3/' > "$add_events"

add_count=$(wc -l < "$add_events" | tr -d ' ')
echo "Found $add_count 'Sending UpdateAddHTLC' events"

grep -E "Closed completed (SETTLE|FAIL) circuit" "$combined_logs" | \
    sed -E 's/.*([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+).*Closed completed (SETTLE|FAIL) circuit for ([0-9a-f]+):.*<-> \([^,]+, ([0-9]+)\).*/\1|\2|\3|\4/' > "$resolve_events"

resolve_count=$(wc -l < "$resolve_events" | tr -d ' ')
echo "Found $resolve_count 'Closed completed SETTLE/FAIL circuit' events"
echo ""

echo "Calculating resolution times..."

awk -F'|' '
function timestamp_to_seconds(ts,    parts, year, month, day, hour, min, sec, frac, days, i) {
    # Parse timestamp: YYYY-MM-DD HH:MM:SS.sss
    # Split on space first
    split(ts, parts, " ")

    # Parse date part
    split(parts[1], date_parts, "-")
    year = date_parts[1]
    month = date_parts[2]
    day = date_parts[3]

    # Parse time part
    split(parts[2], time_parts, ":")
    hour = time_parts[1]
    min = time_parts[2]
    sec = time_parts[3]

    # Extract fractional seconds
    frac = sec - int(sec)
    sec = int(sec)

    # Calculate days since epoch (1970-01-01)
    # Simple approximation - good enough for differences
    days = (year - 1970) * 365 + int((year - 1969) / 4)  # Add leap years

    # Add days for each month
    if (month > 1) days += 31
    if (month > 2) days += (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) ? 29 : 28
    if (month > 3) days += 31
    if (month > 4) days += 30
    if (month > 5) days += 31
    if (month > 6) days += 30
    if (month > 7) days += 31
    if (month > 8) days += 31
    if (month > 9) days += 30
    if (month > 10) days += 31
    if (month > 11) days += 30

    days += day - 1

    # Convert to seconds
    return days * 86400 + hour * 3600 + min * 60 + sec + frac
}

BEGIN {
    # Initialize buckets for SETTLE
    settle_bucket["<1s"] = 0
    settle_bucket["<5s"] = 0
    settle_bucket["<10s"] = 0
    settle_bucket["<30s"] = 0
    settle_bucket["<1min"] = 0
    settle_bucket["<90s"] = 0
    settle_bucket["<2min"] = 0
    settle_bucket["<3min"] = 0
    settle_bucket["<5min"] = 0
    settle_bucket[">5min"] = 0

    # Initialize buckets for FAIL
    fail_bucket["<1s"] = 0
    fail_bucket["<5s"] = 0
    fail_bucket["<10s"] = 0
    fail_bucket["<30s"] = 0
    fail_bucket["<1min"] = 0
    fail_bucket["<90s"] = 0
    fail_bucket["<2min"] = 0
    fail_bucket["<3min"] = 0
    fail_bucket["<5min"] = 0
    fail_bucket[">5min"] = 0

    settle_total = 0
    fail_total = 0
    unmatched = 0
}

# Read add events first
NR == FNR {
    timestamp = $1
    htlc_id = $2
    hash = $3

    # Convert timestamp to seconds
    epoch_float = timestamp_to_seconds(timestamp)

    # Store with composite key: hash:htlc_id
    key = hash ":" htlc_id
    add_times[key] = epoch_float
    next
}

# Read resolve events
{
    timestamp = $1
    outcome = $2
    hash = $3
    out_htlc_id = $4

    # Convert timestamp to seconds
    epoch_float = timestamp_to_seconds(timestamp)

    # Match with add event
    key = hash ":" out_htlc_id

    if (key in add_times) {
        # Calculate resolution time in seconds
        resolution_s = epoch_float - add_times[key]

        # Bucket the resolution time
        bucket = ""
        if (resolution_s < 1) bucket = "<1s"
        else if (resolution_s < 5) bucket = "<5s"
        else if (resolution_s < 10) bucket = "<10s"
        else if (resolution_s < 30) bucket = "<30s"
        else if (resolution_s < 60) bucket = "<1min"
        else if (resolution_s < 90) bucket = "<90s"
        else if (resolution_s < 120) bucket = "<2min"
        else if (resolution_s < 180) bucket = "<3min"
        else if (resolution_s < 300) bucket = "<5min"
        else bucket = ">5min"

        if (outcome == "SETTLE") {
            settle_bucket[bucket]++
            settle_total++
        } else {
            fail_bucket[bucket]++
            fail_total++
        }

        # Clean up
        delete add_times[key]
    } else {
        unmatched++
    }
}

END {
    total = settle_total + fail_total

    # Count unresolved HTLCs (add events with no matching resolve)
    unresolved = 0
    for (key in add_times) {
        unresolved++
    }

    print "HTLC Resolution Time Distribution"
    print "=================================="
    print ""
    print "Total HTLCs analyzed: " total
    if (total > 0) {
        settle_pct = settle_total*100/total
        fail_pct = fail_total*100/total
        # Use 2 decimals for small percentages, 1 for larger ones
        settle_fmt = settle_pct >= 0.1 ? sprintf("%.1f", settle_pct) : sprintf("%.2f", settle_pct)
        fail_fmt = fail_pct >= 0.1 ? sprintf("%.1f", fail_pct) : sprintf("%.2f", fail_pct)
        print "  - SETTLE: " settle_total " (" settle_fmt "%)"
        print "  - FAIL:   " fail_total " (" fail_fmt "%)"
    }
    print "  - Unmatched resolve events: " unmatched
    print "  - Unresolved HTLCs (still in-flight): " unresolved
    print ""

    # Print SETTLE distribution
    print "SETTLE Distribution:"
    print "-------------------"
    printf "%-10s %8s %8s\n", "Bucket", "Count", "Percent"

    pct = settle_total > 0 ? (settle_bucket["<1s"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 1s", settle_bucket["<1s"], pct

    pct = settle_total > 0 ? (settle_bucket["<5s"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 5s", settle_bucket["<5s"], pct

    pct = settle_total > 0 ? (settle_bucket["<10s"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 10s", settle_bucket["<10s"], pct

    pct = settle_total > 0 ? (settle_bucket["<30s"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 30s", settle_bucket["<30s"], pct

    pct = settle_total > 0 ? (settle_bucket["<1min"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 1min", settle_bucket["<1min"], pct

    pct = settle_total > 0 ? (settle_bucket["<90s"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 90s", settle_bucket["<90s"], pct

    pct = settle_total > 0 ? (settle_bucket["<2min"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 2min", settle_bucket["<2min"], pct

    pct = settle_total > 0 ? (settle_bucket["<3min"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 3min", settle_bucket["<3min"], pct

    pct = settle_total > 0 ? (settle_bucket["<5min"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 5min", settle_bucket["<5min"], pct

    pct = settle_total > 0 ? (settle_bucket[">5min"]*100/settle_total) : 0
    printf "%-10s %8d %7.1f%%\n", "> 5min", settle_bucket[">5min"], pct
    print ""

    # Print FAIL distribution
    print "FAIL Distribution:"
    print "-----------------"
    printf "%-10s %8s %8s\n", "Bucket", "Count", "Percent"

    pct = fail_total > 0 ? (fail_bucket["<1s"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 1s", fail_bucket["<1s"], pct

    pct = fail_total > 0 ? (fail_bucket["<5s"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 5s", fail_bucket["<5s"], pct

    pct = fail_total > 0 ? (fail_bucket["<10s"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 10s", fail_bucket["<10s"], pct

    pct = fail_total > 0 ? (fail_bucket["<30s"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 30s", fail_bucket["<30s"], pct

    pct = fail_total > 0 ? (fail_bucket["<1min"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 1min", fail_bucket["<1min"], pct

    pct = fail_total > 0 ? (fail_bucket["<90s"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 90s", fail_bucket["<90s"], pct

    pct = fail_total > 0 ? (fail_bucket["<2min"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 2min", fail_bucket["<2min"], pct

    pct = fail_total > 0 ? (fail_bucket["<3min"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 3min", fail_bucket["<3min"], pct

    pct = fail_total > 0 ? (fail_bucket["<5min"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "< 5min", fail_bucket["<5min"], pct

    pct = fail_total > 0 ? (fail_bucket[">5min"]*100/fail_total) : 0
    printf "%-10s %8d %7.1f%%\n", "> 5min", fail_bucket[">5min"], pct
}
' "$add_events" "$resolve_events" > "$output_file"

cat "$output_file"

rm -rf "$temp_dir"

echo ""
echo "Results written to $output_file"
