# Channel Reputation

This script computes per-channel reputation and revenue scores based on forwarding history.


##  Requirements

* Collect [forwarding history](https://github.com/carlaKC/ln-data/tree/master/forwarding-history)

---

## Run Instructions

**Run the script:**

   ```bash
   python reputation.py --input-csv-file "/path/to/csv"
   ```

The script generates a CSV file named `channel_scores.csv` with the reputation and revenue for each channel.
