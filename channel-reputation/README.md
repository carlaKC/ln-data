# Channel Reputation

This script computes per-channel reputation, revenue, and utilization metrics based on forwarding history and channel capacity data. The final product is `channel_scores.csv` which contains reputation, revenue, liquidity utilization, and slot utilization metrics for each channel.

## LND Instructions

Requirements: access to lnd's [ForwardingHistory API](https://lightning.engineering/api-docs/api/lnd/lightning/forwarding-history) and [ListChannels API](https://lightning.engineering/api-docs/api/lnd/lightning/list-channels), read only macaroon, lncli, [jq](https://jqlang.github.io/jq/), and Python 3.

Ensure that the script is executable:
```bash
chmod +x lnd-data.sh
```

Run `lnd-data.sh` with the following arguments:
```bash
./lnd-data.sh rpcserver macaroonpath tlscertpath [sleep] [start_time]
```

This script will:
1. Collect forwarding history from your node (using `forwarding-history/lnd-data.sh`)
2. Collect channel capacity and HTLC information (using `channel-capacity/channel_capacities.sh`)
3. Calculate reputation metrics for all channels
4. Clean up intermediate files, leaving only `channel_scores.csv`

By default, this script will collect forwarding data from 1 January 2023. If you would like to decrease this range, see the optional `start_time` parameter.

### Performance considerations
If your node is running with bbolt (the default database in LND) and you have a large volume of forwards, you may want to consider setting the optional sleep parameter. This will instruct the data collection to back off for 1 second in between reads, giving other node operations ample time to access the database.

---

## Manual Run Instructions

If you have already collected forwarding history and channel capacity data, you can run the reputation calculation directly:

```bash
python reputation.py /path/to/forwarding_data.csv /path/to/channel_info.csv [output.csv]
```

Arguments:
1. `input_csv_file` (required): CSV file with forwarding events
2. `channel_info_file` (required): CSV file with channel capacity and HTLC info
3. `output_csv_file` (optional): Output CSV file name (default: `channel_scores.csv`)

### Channel Info Format
The channel info CSV should have columns: `short_channel_id`, `capacity`, `max_accepted_htlcs`
- Not all channels need to be included in this CSV
- For channels missing from the CSV, liquidity utilization will be 0
- Other metrics (reputation, revenue, slot utilization) are calculated for all channels
