#!/usr/bin/env python3

import csv
import argparse
import heapq
from collections import defaultdict
import sys

HTLC_RESOLUTION_TIME = 60  # seconds

# Slot buckets (exact counts)
SLOT_BUCKETS = [0, 1, 2, 5, 10, 20, 50, 100, 200, 400]

# Liquidity buckets (exact percentages)
LIQUIDITY_BUCKETS = [0, 0.5, 1, 2, 5, 10, 15, 25, 50, 75, 90, 95]


class StateTracker:
    """Tracks time spent in different states."""
    def __init__(self, initial_state, start_time: float):
        self.state_changes = [(start_time, initial_state)]

    def add_state_change(self, timestamp: float, new_state):
        if len(self.state_changes) == 0 or self.state_changes[-1][1] != new_state:
            self.state_changes.append((timestamp, new_state))

    def calculate_time_in_buckets(self, end_time: float, buckets, bucket_fn):
        """Calculate time spent in each bucket."""
        bucket_times = {bucket: 0.0 for bucket in buckets}
        bucket_times[">max"] = 0.0  # For values above the largest bucket

        total_time = 0.0

        for i in range(len(self.state_changes)):
            current_time, current_state = self.state_changes[i]
            if i < len(self.state_changes) - 1:
                duration = self.state_changes[i + 1][0] - current_time
            else:
                duration = end_time - current_time

            if duration < 0:
                continue

            total_time += duration

            # Determine which bucket this state falls into
            bucket = bucket_fn(current_state, buckets)
            bucket_times[bucket] += duration

        return bucket_times, total_time


class DirectionalHTLCManager:
    """Manages HTLC slots and liquidity for channels."""
    def __init__(self, resolution_time: float):
        self.resolution_time = resolution_time
        self.pending_resolutions = []
        self.current_slots_in = defaultdict(int)
        self.current_slots_out = defaultdict(int)
        self.current_liquidity_in = defaultdict(float)
        self.current_liquidity_out = defaultdict(float)

    def add_htlc(self, timestamp: float, channel_id: str, amount_msat: int, direction: str):
        resolution_ts = timestamp + self.resolution_time
        heapq.heappush(self.pending_resolutions, (resolution_ts, amount_msat, channel_id, direction))

        if direction == 'in':
            self.current_slots_in[channel_id] += 1
            self.current_liquidity_in[channel_id] += amount_msat
        else:
            self.current_slots_out[channel_id] += 1
            self.current_liquidity_out[channel_id] += amount_msat

    def process_resolutions(self, current_time: float):
        resolved = []

        while self.pending_resolutions and self.pending_resolutions[0][0] <= current_time:
            resolution_ts, amount_msat, channel_id, direction = heapq.heappop(self.pending_resolutions)

            if direction == 'in':
                self.current_slots_in[channel_id] -= 1
                self.current_liquidity_in[channel_id] -= amount_msat
            else:
                self.current_slots_out[channel_id] -= 1
                self.current_liquidity_out[channel_id] -= amount_msat

            resolved.append((resolution_ts, channel_id, amount_msat, direction))

        return resolved

    def get_current_state(self, channel_id: str):
        return (
            self.current_slots_in[channel_id],
            self.current_slots_out[channel_id],
            self.current_liquidity_in[channel_id],
            self.current_liquidity_out[channel_id]
        )


def read_forwards_from_csv(input_csv_file: str):
    forwards = []
    with open(input_csv_file, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row = {key.strip(): value.strip().strip('"') for key, value in row.items()}
            forwards.append({
                'timestamp': int(row['timestamp_ns']) / 1e9,
                'chan_id_in': row['chan_id_in'],
                'chan_id_out': row['chan_id_out'],
                'amt_in_msat': int(row['amt_in_msat']),
                'amt_out_msat': int(row['amt_out_msat']),
            })
    return forwards


def read_channel_info_from_csv(channel_info_file: str):
    """Read channel capacity and max HTLC info."""
    channel_info = {}
    with open(channel_info_file, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            row = {key.strip(): value.strip().strip('"') for key, value in row.items()}
            chan_id = row['short_channel_id']
            channel_info[chan_id] = {
                'capacity': int(row['capacity']),
                'max_htlcs': int(row['max_accepted_htlcs']),
            }
    return channel_info


def slot_bucket_fn(slot_count, buckets):
    """Determine which slot bucket a count falls into (exact match)."""
    # Find the bucket this count belongs to
    for i, bucket in enumerate(buckets):
        if slot_count == bucket:
            return bucket
        if i < len(buckets) - 1:
            # Check if it falls between this bucket and the next
            if bucket < slot_count < buckets[i + 1]:
                return bucket
        else:
            # Beyond the last bucket
            if slot_count > bucket:
                return ">max"
    return buckets[0]  # Default to first bucket


def liquidity_bucket_fn(liq_pct, buckets):
    """Determine which liquidity bucket a percentage falls into.

    Bucket semantics: bucket B contains values in range (prev_bucket, B].
    Bucket 0 contains values that are essentially 0 (< 0.001%).
    """
    # Treat values below 0.001% as essentially 0
    if liq_pct < 0.001:
        return 0

    # Find the appropriate bucket (bucket represents upper bound of range)
    for bucket in buckets:
        if bucket == 0:
            continue  # Already handled above
        if liq_pct <= bucket:
            return bucket

    return ">max"


def format_slot_bucket(bucket):
    """Format slot bucket for display."""
    if bucket == ">max":
        return f"> {SLOT_BUCKETS[-1]}"
    if bucket == 0:
        return "0"
    # Find this bucket's position
    idx = SLOT_BUCKETS.index(bucket) if bucket in SLOT_BUCKETS else -1
    if idx > 0:
        prev_bucket = SLOT_BUCKETS[idx - 1]
        start = prev_bucket + 1
        if start == bucket:
            return f"{bucket}"  # Single value bucket
        return f"{start}-{bucket}"
    return f"{bucket}"


def format_liquidity_bucket(bucket):
    """Format liquidity bucket for display."""
    if bucket == ">max":
        return f"> {LIQUIDITY_BUCKETS[-1]}%"
    if bucket == 0:
        return "~0%"
    # Find this bucket's position
    idx = LIQUIDITY_BUCKETS.index(bucket) if bucket in LIQUIDITY_BUCKETS else -1
    if idx > 0:
        prev_bucket = LIQUIDITY_BUCKETS[idx - 1]
        if prev_bucket == 0:
            return f">0-{bucket}%"
        return f">{prev_bucket}-{bucket}%"
    return f"{bucket}%"


def main():
    parser = argparse.ArgumentParser(description="Calculate channel utilization distributions")
    parser.add_argument("input_csv_file", help="Forwarding events CSV file")
    parser.add_argument("channel_info_file", help="Channel capacity info CSV file")
    parser.add_argument("--output", default=None, help="Output file (default: auto-generated based on resolution time)")
    parser.add_argument("--htlc-resolution-time", type=float, default=HTLC_RESOLUTION_TIME,
                        help=f"HTLC resolution time in seconds (default: {HTLC_RESOLUTION_TIME})")
    args = parser.parse_args()

    # Generate output filename if not specified
    if args.output is None:
        resolution_time_label = f"{int(args.htlc_resolution_time)}s" if args.htlc_resolution_time >= 1 else f"{args.htlc_resolution_time:.1f}s"
        args.output = f"channel_utilization_distribution_{resolution_time_label}.txt"

    # Load channel info
    print(f"Loading channel info from {args.channel_info_file}...")
    channel_info = read_channel_info_from_csv(args.channel_info_file)
    print(f"Loaded info for {len(channel_info)} channels")

    # Load forwards
    print(f"Loading forwards from {args.input_csv_file}...")
    forwards = read_forwards_from_csv(args.input_csv_file)
    print(f"Loaded {len(forwards)} forwards")

    if len(forwards) == 0:
        print("No forwards found.")
        return

    # Sort by timestamp
    forwards.sort(key=lambda x: x['timestamp'])

    actual_start_ts = forwards[0]['timestamp']
    actual_end_ts = forwards[-1]['timestamp']

    # Initialize tracking (only for incoming channels)
    slot_states = {}
    liquidity_states = {}
    htlc_manager = DirectionalHTLCManager(args.htlc_resolution_time)

    print("Processing forwards...")

    for fwd in forwards:
        timestamp = fwd['timestamp']
        amt_in_msat = fwd['amt_in_msat']

        # Process HTLC resolutions
        resolutions = htlc_manager.process_resolutions(timestamp)
        for resolution_ts, chan_id, resolved_amt, direction in resolutions:
            slots_in, slots_out, liq_in, liq_out = htlc_manager.get_current_state(chan_id)
            total_slots = slots_in + slots_out
            total_liq = liq_in + liq_out

            if chan_id in slot_states:
                slot_states[chan_id].add_state_change(resolution_ts, total_slots)

            if chan_id in liquidity_states and chan_id in channel_info:
                capacity_msat = channel_info[chan_id]['capacity'] * 1000
                liq_pct = (total_liq / capacity_msat) * 100 if capacity_msat > 0 else 0
                liquidity_states[chan_id].add_state_change(resolution_ts, liq_pct)

        # Process incoming channel only
        if 'chan_id_in' in fwd and fwd['chan_id_in']:
            chan_in = str(fwd['chan_id_in'])

            if chan_in not in slot_states:
                slot_states[chan_in] = StateTracker(0, actual_start_ts)
                liquidity_states[chan_in] = StateTracker(0.0, actual_start_ts)

            htlc_manager.add_htlc(timestamp, chan_in, amt_in_msat, 'out')

            slots_in, slots_out, liq_in, liq_out = htlc_manager.get_current_state(chan_in)
            total_slots = slots_in + slots_out
            total_liq = liq_in + liq_out

            slot_states[chan_in].add_state_change(timestamp, total_slots)

            if chan_in in channel_info:
                capacity_msat = channel_info[chan_in]['capacity'] * 1000
                liq_pct = (total_liq / capacity_msat) * 100 if capacity_msat > 0 else 0
                liquidity_states[chan_in].add_state_change(timestamp, liq_pct)

    # Process final resolutions
    final_time = actual_end_ts + args.htlc_resolution_time * 2
    resolutions = htlc_manager.process_resolutions(final_time)
    for resolution_ts, chan_id, resolved_amt, direction in resolutions:
        slots_in, slots_out, liq_in, liq_out = htlc_manager.get_current_state(chan_id)
        total_slots = slots_in + slots_out
        total_liq = liq_in + liq_out

        if chan_id in slot_states:
            slot_states[chan_id].add_state_change(resolution_ts, total_slots)

        if chan_id in liquidity_states and chan_id in channel_info:
            capacity_msat = channel_info[chan_id]['capacity'] * 1000
            liq_pct = (total_liq / capacity_msat) * 100 if capacity_msat > 0 else 0
            liquidity_states[chan_id].add_state_change(resolution_ts, liq_pct)

    # Calculate distributions
    print("Calculating distributions...")

    all_channels = sorted(slot_states.keys())

    # Aggregate across all channels
    slot_bucket_times = {bucket: 0.0 for bucket in SLOT_BUCKETS}
    slot_bucket_times[">max"] = 0.0

    liq_bucket_times = {bucket: 0.0 for bucket in LIQUIDITY_BUCKETS}
    liq_bucket_times[">max"] = 0.0

    total_time = 0.0

    for chan_id in all_channels:
        # Slots
        bucket_times, chan_time = slot_states[chan_id].calculate_time_in_buckets(
            final_time, SLOT_BUCKETS, slot_bucket_fn)
        for bucket, time_val in bucket_times.items():
            slot_bucket_times[bucket] += time_val

        # Liquidity
        bucket_times, chan_time = liquidity_states[chan_id].calculate_time_in_buckets(
            final_time, LIQUIDITY_BUCKETS, liquidity_bucket_fn)
        for bucket, time_val in bucket_times.items():
            liq_bucket_times[bucket] += time_val

        total_time += chan_time

    # Generate report
    lines = []
    lines.append("Incoming Channel Utilization Distribution")
    lines.append("==========================================")
    lines.append("")
    lines.append(f"Total incoming channels analyzed: {len(all_channels)}")
    lines.append(f"Total observation time: {total_time:.0f} seconds ({total_time / 3600:.1f} hours)")
    lines.append("")

    # Slot distribution
    lines.append("Slot Utilization:")
    lines.append("-----------------")
    lines.append(f"{'Slots':<15} {'Time (seconds)':>15} {'Percent':>10}")

    for bucket in SLOT_BUCKETS + [">max"]:
        time_val = slot_bucket_times[bucket]
        pct = (time_val / total_time * 100) if total_time > 0 else 0
        bucket_label = format_slot_bucket(bucket)
        lines.append(f"{bucket_label:<15} {time_val:>15.0f} {pct:>9.2f}%")

    lines.append("")

    # Liquidity distribution
    lines.append("Liquidity Utilization:")
    lines.append("----------------------")
    lines.append(f"{'Liquidity':<15} {'Time (seconds)':>15} {'Percent':>10}")

    for bucket in LIQUIDITY_BUCKETS + [">max"]:
        time_val = liq_bucket_times[bucket]
        pct = (time_val / total_time * 100) if total_time > 0 else 0
        bucket_label = format_liquidity_bucket(bucket)
        lines.append(f"{bucket_label:<15} {time_val:>15.0f} {pct:>9.2f}%")

    # Write to file
    report = "\n".join(lines)
    with open(args.output, 'w') as f:
        f.write(report)

    print(f"Results written to {args.output}")


if __name__ == "__main__":
    main()
