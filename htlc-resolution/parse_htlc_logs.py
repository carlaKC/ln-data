#!/usr/bin/env python3

import os
import sys
import re
import gzip
from datetime import datetime
from collections import defaultdict
from pathlib import Path


def parse_timestamp(ts_str):
    """Parse timestamp string to seconds since epoch (float)."""
    # Format: YYYY-MM-DD HH:MM:SS.sss
    dt = datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S.%f")
    return dt.timestamp()


def find_log_files(logs_dir):
    """Find all lnd.log* files in the directory, sorted."""
    path = Path(logs_dir)
    log_files = sorted(path.glob("lnd.log*"))
    return log_files


def read_log_file(filepath):
    """Read a log file, handling gzip compression."""
    if filepath.suffix == ".gz":
        with gzip.open(filepath, 'rt', encoding='utf-8', errors='ignore') as f:
            return f.readlines()
    else:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            return f.readlines()


def extract_add_events(log_lines):
    """Extract 'Sending UpdateAddHTLC' events."""
    # Pattern: timestamp ... id=<htlc_id> ... hash=<hash>
    pattern = re.compile(
        r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+).*?'
        r'Sending UpdateAddHTLC.*?'
        r'id=(\d+).*?'
        r'hash=([0-9a-f]+)'
    )

    events = []
    for line in log_lines:
        if "Sending UpdateAddHTLC" in line:
            match = pattern.search(line)
            if match:
                timestamp_str = match.group(1)
                htlc_id = match.group(2)
                hash_val = match.group(3)
                events.append({
                    'timestamp': parse_timestamp(timestamp_str),
                    'htlc_id': htlc_id,
                    'hash': hash_val
                })

    return events


def extract_resolve_events(log_lines):
    """Extract 'Closed completed (SETTLE|FAIL) circuit' events."""
    # Pattern: timestamp ... Closed completed (SETTLE|FAIL) circuit for <hash>:... <-> (..., <htlc_id>)
    pattern = re.compile(
        r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+).*?'
        r'Closed completed (SETTLE|FAIL) circuit for '
        r'([0-9a-f]+):.*?'
        r'<-> \([^,]+, (\d+)\)'
    )

    events = []
    for line in log_lines:
        if "Closed completed" in line and "circuit" in line:
            match = pattern.search(line)
            if match:
                timestamp_str = match.group(1)
                outcome = match.group(2)
                hash_val = match.group(3)
                htlc_id = match.group(4)
                events.append({
                    'timestamp': parse_timestamp(timestamp_str),
                    'outcome': outcome,
                    'hash': hash_val,
                    'htlc_id': htlc_id
                })

    return events


def bucket_resolution_time(seconds):
    """Bucket resolution time into predefined buckets."""
    if seconds < 1:
        return "< 1s"
    elif seconds < 5:
        return "< 5s"
    elif seconds < 10:
        return "< 10s"
    elif seconds < 30:
        return "< 30s"
    elif seconds < 60:
        return "< 1min"
    elif seconds < 90:
        return "< 90s"
    elif seconds < 120:
        return "< 2min"
    elif seconds < 180:
        return "< 3min"
    elif seconds < 300:
        return "< 5min"
    else:
        return "> 5min"


def calculate_resolution_stats(add_events, resolve_events):
    """Match add and resolve events, calculate resolution times."""
    # Build index of add events: key = hash:htlc_id
    add_times = {}
    for event in add_events:
        key = f"{event['hash']}:{event['htlc_id']}"
        add_times[key] = event['timestamp']

    # Define buckets
    buckets = ["< 1s", "< 5s", "< 10s", "< 30s", "< 1min", "< 90s", "< 2min", "< 3min", "< 5min", "> 5min"]
    settle_buckets = {bucket: 0 for bucket in buckets}
    fail_buckets = {bucket: 0 for bucket in buckets}

    settle_total = 0
    fail_total = 0
    unmatched = 0

    # Process resolve events
    for event in resolve_events:
        key = f"{event['hash']}:{event['htlc_id']}"

        if key in add_times:
            resolution_time = event['timestamp'] - add_times[key]
            bucket = bucket_resolution_time(resolution_time)

            if event['outcome'] == "SETTLE":
                settle_buckets[bucket] += 1
                settle_total += 1
            else:  # FAIL
                fail_buckets[bucket] += 1
                fail_total += 1

            # Remove matched event
            del add_times[key]
        else:
            unmatched += 1

    # Count unresolved HTLCs (add events with no matching resolve)
    unresolved = len(add_times)

    return {
        'settle_buckets': settle_buckets,
        'fail_buckets': fail_buckets,
        'settle_total': settle_total,
        'fail_total': fail_total,
        'unmatched': unmatched,
        'unresolved': unresolved
    }


def format_percentage(value, total):
    """Format percentage with appropriate decimal places."""
    if total == 0:
        return 0.0
    pct = (value * 100.0) / total
    return pct


def generate_report(stats, output_file):
    """Generate and write the resolution time distribution report."""
    settle_buckets = stats['settle_buckets']
    fail_buckets = stats['fail_buckets']
    settle_total = stats['settle_total']
    fail_total = stats['fail_total']
    total = settle_total + fail_total
    unmatched = stats['unmatched']
    unresolved = stats['unresolved']

    buckets = ["< 1s", "< 5s", "< 10s", "< 30s", "< 1min", "< 90s", "< 2min", "< 3min", "< 5min", "> 5min"]

    lines = []
    lines.append("HTLC Resolution Time Distribution")
    lines.append("==================================")
    lines.append("")
    lines.append(f"Total HTLCs analyzed: {total}")

    if total > 0:
        settle_pct = format_percentage(settle_total, total)
        fail_pct = format_percentage(fail_total, total)
        settle_fmt = f"{settle_pct:.1f}" if settle_pct >= 0.1 else f"{settle_pct:.2f}"
        fail_fmt = f"{fail_pct:.1f}" if fail_pct >= 0.1 else f"{fail_pct:.2f}"
        lines.append(f"  - SETTLE: {settle_total} ({settle_fmt}%)")
        lines.append(f"  - FAIL:   {fail_total} ({fail_fmt}%)")

    lines.append(f"  - Unmatched resolve events: {unmatched}")
    lines.append(f"  - Unresolved HTLCs (still in-flight): {unresolved}")
    lines.append("")

    # SETTLE distribution
    lines.append("SETTLE Distribution:")
    lines.append("-------------------")
    lines.append(f"{'Bucket':<10} {'Count':>8} {'Percent':>8}")

    for bucket in buckets:
        count = settle_buckets[bucket]
        pct = format_percentage(count, settle_total)
        lines.append(f"{bucket:<10} {count:>8} {pct:>7.1f}%")

    lines.append("")

    # FAIL distribution
    lines.append("FAIL Distribution:")
    lines.append("-----------------")
    lines.append(f"{'Bucket':<10} {'Count':>8} {'Percent':>8}")

    for bucket in buckets:
        count = fail_buckets[bucket]
        pct = format_percentage(count, fail_total)
        lines.append(f"{bucket:<10} {count:>8} {pct:>7.1f}%")

    # Write to file
    report = "\n".join(lines)
    with open(output_file, 'w') as f:
        f.write(report)

    return report


def main():
    # Parse arguments
    logs_dir = sys.argv[1] if len(sys.argv) > 1 else "htlc-resolution/logs"
    output_file = sys.argv[2] if len(sys.argv) > 2 else "htlc_resolution_distribution.txt"

    # Check if logs directory exists
    if not os.path.isdir(logs_dir):
        print(f"Error: Logs directory not found at {logs_dir}")
        print("")
        print(f"Usage: {sys.argv[0]} [logs-directory] [output-file]")
        print(f"Example: {sys.argv[0]} logs htlc_resolution_distribution.txt")
        print("")
        print("Note: Please copy your LND logs into the ./logs directory first")
        sys.exit(1)

    print(f"Processing LND logs from {logs_dir}...")

    # Find log files
    log_files = find_log_files(logs_dir)

    if not log_files:
        print(f"Error: No log files found in {logs_dir}")
        sys.exit(1)

    print("Found log files:")
    for log_file in log_files:
        print(f"  - {log_file.name}")
    print("")

    # Read and combine all log files
    print("Combining log files in chronological order...")
    all_lines = []
    for log_file in log_files:
        if log_file.suffix == ".gz":
            print(f"Processing gzipped: {log_file.name}")
        else:
            print(f"Processing regular: {log_file.name}")

        lines = read_log_file(log_file)
        all_lines.extend(lines)

    print(f"Combined log size: {len(all_lines)} lines")
    print("")

    # Extract events
    print("Extracting HTLC events...")
    add_events = extract_add_events(all_lines)
    print(f"Found {len(add_events)} 'Sending UpdateAddHTLC' events")

    resolve_events = extract_resolve_events(all_lines)
    print(f"Found {len(resolve_events)} 'Closed completed SETTLE/FAIL circuit' events")
    print("")

    # Calculate statistics
    print("Calculating resolution times...")
    stats = calculate_resolution_stats(add_events, resolve_events)

    # Generate report
    generate_report(stats, output_file)

    print("")
    print(f"Results written to {output_file}")


if __name__ == "__main__":
    main()
