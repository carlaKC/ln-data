import os
import time
import csv
import hashlib
import datetime as dt
from collections import defaultdict
import argparse
import codecs
import json

REVENUE_WINDOW_SECS = 60 * 60 * 24 * 14  # 2 weeks
REPUTATION_MULTIPLIER = 12
LOOKBACK_MONTHS = 6
CSV_FILE = "channel_scores.csv"
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
                row = {key.strip(): value.strip() for key, value in row.items()}
                forwards.append({
                    'timestamp': int(row['timestamp_ns']) / 1e9,  # Convert ns to seconds
                    'chan_id_in': row['chan_id_in'],
                    'chan_id_out': row['chan_id_out'],
                    'fee_msat': int(row['fee_msat']),
                })
    except Exception as e:
        print(f"Error reading forwards CSV: {e}")
    return forwards


def main():
    parser = argparse.ArgumentParser(description="Calculate channel reputation and revenue from LND forwards.")
    parser.add_argument("--csv-file", default=CSV_FILE, help="Output CSV file name (default: channel_scores.csv)")
    parser.add_argument("--input-csv-file", default=INPUT_CSV_FILE, help="Input CSV file with forwarding events (default: forwarding_data.csv)")
    args = parser.parse_args()

    now_dt = dt.datetime.now(dt.UTC)
    end_ts = int(now_dt.timestamp())
    start_dt = now_dt - dt.timedelta(days=30 * LOOKBACK_MONTHS)
    start_ts = int(start_dt.timestamp())

    print(f"Reading forwards from {args.input_csv_file}...")
    forwards = read_forwards_from_csv(args.input_csv_file)
    print(f"Fetched {len(forwards)} forwards.")

    channels = defaultdict(lambda: {
        "reputation": DecayingAverage(REVENUE_WINDOW_SECS * REPUTATION_MULTIPLIER),
        "revenue": RevenueAverage(start_ts, REVENUE_WINDOW_SECS, REPUTATION_MULTIPLIER),
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

    with open(args.csv_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["channel_id_hash", "reputation", "revenue"])
        now_ts = time.time()
        for cid, data in channels.items():
            rep = int(round(data["reputation"].value_at(now_ts)))
            rev = int(round(data["revenue"].value_at(now_ts)))
            writer.writerow([cid, rep, rev])

    print(f"Wrote {len(channels)} channels to {args.csv_file}")


if __name__ == "__main__":
    main()

