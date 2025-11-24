# Channel Reputation

This script computes per-channel reputation, revenue, and utilization metrics based on forwarding history.


##  Requirements

* Collect [forwarding history](https://github.com/carlaKC/ln-data/tree/master/forwarding-history)
* Channel info CSV with columns: `short_channel_id`, `capacity`, `max_accepted_htlcs`
  - Not all channels need to be included in this CSV
  - For channels missing from the CSV, liquidity utilization will be 0
  - Other metrics (reputation, revenue, slot utilization) are calculated for all channels

---

## Run Instructions

**Run the script:**

   ```bash
   python reputation.py /path/to/forwarding_data.csv /path/to/channel_info.csv [output.csv]
   ```

Arguments:
1. `input_csv_file` (required): CSV file with forwarding events
2. `channel_info_file` (required): CSV file with channel capacity and HTLC info
3. `output_csv_file` (optional): Output CSV file name (default: `channel_scores.csv`)
