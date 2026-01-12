## Incoming Channel Utilization Distribution

This script analyzes how incoming channel HTLC slots and liquidity are utilized over time, producing a distribution similar to the HTLC resolution time distribution.

### What it tracks

For each incoming channel (chan_id_in from forwards), the script tracks:

**Slot Utilization** - Number of HTLCs in-flight on incoming channels:
- Buckets: 0, 1, 2, 3-5, 6-10, 11-20, 21-50, 51-100, 101-200, 201-400, > 400

**Liquidity Utilization** - Percentage of channel capacity in use on incoming channels:
- Buckets: 0%, 0.1-0.5%, 0.6-1%, 1.1-2%, 2.1-5%, 5.1-10%, 10.1-15%, 15.1-25%, 25.1-50%, 50.1-75%, 75.1-90%, 90.1-95%, > 95%

### Run Instructions

```bash
python calculate_utilization.py <forwarding_events.csv> <channel_capacities.csv> [--output <file>]
```

Example:
```bash
python calculate_utilization.py ../forwarding-history/forwarding_events.csv ../channel-capacity/channel_capacities.csv --output channel_utilization_distribution.txt
```

### Options

- `--output` - Output file name (default: auto-generated as `channel_utilization_distribution_<time>s.txt`)
- `--htlc-resolution-time` - HTLC resolution time in seconds (default: 60)

The HTLC resolution time determines how long HTLCs are assumed to be in-flight. This affects utilization calculations:
- **1 second**: More conservative, assumes HTLCs resolve quickly
- **60 seconds**: More pessimistic, assumes HTLCs take longer to resolve

### Output Format

The output shows the percentage of time that channels spent in each utilization bucket, aggregated across all channels.

Example output:
```
Slot Utilization (Inbound):
---------------------------
Bucket          Time (seconds)    Percent
<= 1                    45000      89.50%
<= 2                     3500       6.95%
...
```

This tells you that channels spent 89.5% of the time with 1 or fewer inbound HTLCs in flight.
