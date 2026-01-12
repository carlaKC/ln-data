import time
import csv
import datetime as dt
import os
from collections import defaultdict
import argparse

REVENUE_WINDOW_SECS = 60 * 60 * 24 * 14  # 2 weeks
REPUTATION_MULTIPLIER = 12
INPUT_CSV_FILE = "forwarding_data.csv"

class DecayingAverage:
    def __init__(self, period_secs: float):
        self.value = 0.0
        self.last_updated = None
        self.decay_rate = 0.5 ** (2.0 / period_secs)

    def value_at(self, now_ts: float):
        if self.last_updated is None:
            self.last_updated = now_ts
            return self.value
        elapsed = now_ts - self.last_updated
        if elapsed < 0:
            if abs(elapsed) > 1.0:
                raise ValueError("Update attempted in the past")
            return self.value
        self.value *= (self.decay_rate ** elapsed)
        self.last_updated = now_ts
        return self.value

    def add_value(self, val: float, now_ts: float):
        self.value_at(now_ts)
        self.value += val
        self.last_updated = now_ts
        return self.value


class RevenueAverage:
    """Implements the rolling decayed revenue average across multiple windows."""
    def __init__(self, start_ts: float, revenue_window_secs: float, multiplier: int):
        self.start_ts = start_ts
        self.window_count = multiplier
        self.window_duration = revenue_window_secs
        self.aggregated = DecayingAverage(revenue_window_secs * multiplier)

    def add_value(self, val: float, now_ts: float):
        return self.aggregated.add_value(val, now_ts)

    def windows_tracked(self, now_ts: float) -> float:
        return (now_ts - self.start_ts) / self.window_duration

    def value_at(self, now_ts: float) -> float:
        tracked = self.windows_tracked(now_ts)
        divisor = min(max(tracked, 1.0), float(self.window_count))
        decayed = self.aggregated.value_at(now_ts)
        return decayed / divisor


def read_forwards_from_csv(input_csv_file: str):
    forwards = []
    try:
        with open(input_csv_file, newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            for row in reader:
                row = {key.strip(): value.strip().strip('"') for key, value in row.items()}
                forwards.append({
                    'timestamp': int(row['timestamp_ns']) / 1e9,  # Convert ns to seconds
                    'chan_id_in': row['chan_id_in'],
                    'chan_id_out': row['chan_id_out'],
                    'fee_msat': int(row['fee_msat']),
                })
    except Exception as e:
        print(f"Error reading forwards CSV: {e}")
    return forwards


def calculate_and_write_scores(input_csv_file: str, output_file: str, revenue_window_secs: int, reputation_multiplier: int, append_mode: bool = False):
    """Calculate channel reputation and revenue scores and write to CSV.
    
    Args:
        input_csv_file: Path to input CSV with forwarding events
        output_file: Path to output CSV file
        revenue_window_secs: Revenue window in seconds
        reputation_multiplier: Reputation multiplier
        append_mode: If True, append to file; if False, overwrite file
    """
    try:
        now_dt = dt.datetime.now(dt.timezone.utc)
    except AttributeError:
        # Fallback for Python < 3.2
        now_dt = dt.datetime.utcnow().replace(tzinfo=dt.timezone.utc)
    # Calculate lookback period from revenue window and multiplier
    lookback_secs = revenue_window_secs * reputation_multiplier
    start_dt = now_dt - dt.timedelta(seconds=lookback_secs)
    start_ts = int(start_dt.timestamp())

    print(f"Reading forwards from {input_csv_file}...")
    forwards = read_forwards_from_csv(input_csv_file)
    print(f"Fetched {len(forwards)} forwards.")

    channels = defaultdict(lambda: {
        "reputation": DecayingAverage(revenue_window_secs * reputation_multiplier),
        "revenue": RevenueAverage(start_ts, revenue_window_secs, reputation_multiplier),
    })

    for fwd in forwards:
        fee_msat = fwd.get('fee_msat', 0)
        timestamp = fwd.get('timestamp', 0)

        # Outgoing link → Reputation
        if 'chan_id_out' in fwd and fwd['chan_id_out']:
            chan_out = str(fwd['chan_id_out'])
            channels[chan_out]["reputation"].add_value(fee_msat, timestamp)

        # Incoming link → Revenue
        if 'chan_id_in' in fwd and fwd['chan_id_in']:
            chan_in = str(fwd['chan_id_in'])
            channels[chan_in]["revenue"].add_value(fee_msat, timestamp)

    # Create sorted channel ID mapping (for anonymization)
    sorted_channel_ids = sorted(channels.keys())
    channel_id_mapping = {cid: idx + 1 for idx, cid in enumerate(sorted_channel_ids)}

    # Determine file mode and whether to write header
    file_mode = "a" if append_mode else "w"
    write_header = not append_mode or not os.path.exists(output_file)
    
    # Get current timestamp for this snapshot
    now_ts = time.time()
    try:
        timestamp_str = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    except AttributeError:
        # Fallback for Python < 3.2
        timestamp_str = dt.datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

    with open(output_file, file_mode, newline="") as f:
        writer = csv.writer(f)
        if write_header:
            writer.writerow(["timestamp", "channel_id", "reputation", "revenue"])
        # Write in sorted order by mapped ID
        for cid in sorted_channel_ids:
            data = channels[cid]
            mapped_id = channel_id_mapping[cid]
            rep = int(round(data["reputation"].value_at(now_ts)))
            rev = int(round(data["revenue"].value_at(now_ts)))
            writer.writerow([timestamp_str, mapped_id, rep, rev])

    print(f"Wrote {len(channels)} channels to {output_file} at {timestamp_str}")


def main():
    parser = argparse.ArgumentParser(description="Calculate channel reputation and revenue from LND forwards.")
    parser.add_argument("--csv-file", default=None, help="Output CSV file name (default: auto-generated based on window parameters)")
    parser.add_argument("--input-csv-file", default=INPUT_CSV_FILE, help="Input CSV file with forwarding events (default: forwarding_data.csv)")
    parser.add_argument("--revenue-window-secs", type=int, default=REVENUE_WINDOW_SECS, help=f"Revenue window in seconds (default: {REVENUE_WINDOW_SECS}, which is 2 weeks)")
    parser.add_argument("--reputation-multiplier", type=int, default=REPUTATION_MULTIPLIER, help=f"Reputation multiplier (default: {REPUTATION_MULTIPLIER})")
    parser.add_argument("--interval", type=int, default=None, help="Run periodically with this interval in seconds (e.g., 3600 for hourly, 86400 for daily)")
    args = parser.parse_args()

    revenue_window_secs = args.revenue_window_secs
    reputation_multiplier = args.reputation_multiplier

    # Calculate windows in days
    revenue_window_days = revenue_window_secs / (24 * 60 * 60)
    reputation_window_days = (revenue_window_secs * reputation_multiplier) / (24 * 60 * 60)

    # Generate output filename if not specified
    if args.csv_file is None:
        output_file = f"channel_scores_{revenue_window_days:.0f}days_{reputation_window_days:.0f}days.csv"
    else:
        output_file = args.csv_file

    # Determine if we're in periodic mode
    append_mode = args.interval is not None

    if args.interval is not None:
        # Periodic execution mode
        print(f"Running in periodic mode with interval of {args.interval} seconds")
        print(f"Press Ctrl+C to stop")
        try:
            while True:
                calculate_and_write_scores(
                    args.input_csv_file,
                    output_file,
                    revenue_window_secs,
                    reputation_multiplier,
                    append_mode=True
                )
                print(f"Sleeping for {args.interval} seconds...")
                time.sleep(args.interval)
        except KeyboardInterrupt:
            print("\nStopped by user")
    else:
        # Single run mode (backward compatible)
        calculate_and_write_scores(
            args.input_csv_file,
            output_file,
            revenue_window_secs,
            reputation_multiplier,
            append_mode=False
        )


if __name__ == "__main__":
    main()
