# LN Data Collection

This repo contains scripts that can be used to collect, export and 
pseudonymize data from LND for research purposes. 

It will collect the following data:
- The amount of time that HTLCs forwarded through your node take to
  resolve.
- Information about the amount of liquidity and slots used on your
  channels.
- Reputation scores using our proposed [algorithm](https://github.com/lightning/bolts/pull/1280).

*Channel IDs are hidden*.

## Quick Start

You will need access to the following:
- The directory containing your LND node's logs
- A read-only macaroon for LND
- A TLS certificate for LND
- [jq](https://jqlang.org/) installed
- [Python](https://www.python.org/) installed

### Step 1: Copy Your LND Logs

Out of an abundance of caution, we suggest that you copy your LND logs:
```sh
cp -r /path/to/.lnd/logs/bitcoin/mainnet/*.log* htlc-resolution/logs/
```

### Step 2: Run the Data Collection Script

Make the script executable and run it:
```sh
chmod +x reputation_data.sh
./reputation_data.sh rpcserver macaroonpath tlscertpath
```

**Optional parameters:**

If you are running a node that forwards many payments using bbolt (LND's
default database), consider adding a sleep period of 1-2 seconds for
fetching forwarding history to lighten the load:

```sh
./reputation_data.sh rpcserver macaroonpath tlscertpath [sleep_seconds]
```

Results are collected from 1 January 2024 by default. You can specify a
different start time by providing the unix timestamp in seconds:

```sh
./reputation_data.sh rpcserver macaroonpath tlscertpath [sleep_seconds] [start_time_unix_seconds]
```

### What the script does

The script will automatically:
1. Parse HTLC resolution times from your logs
2. Collect forwarding history from your node
3. Collect channel capacity information
4. Calculate channel reputation scores (3 different configurations)
5. Calculate channel utilization distributions (2 different HTLC resolution time assumptions)

All results will be written to the `results/` directory.

### Results

Please send us all the files in the `results/` directory!

You should expect the following files:
- `htlc_resolution_distribution.txt` - HTLC resolution time analysis
- `channel_scores_14days_168days.csv` - Reputation scores (2 week revenue window, 12x multiplier)
- `channel_scores_28days_336days.csv` - Reputation scores (4 week revenue window, 12x multiplier)
- `channel_scores_14days_336days.csv` - Reputation scores (2 week revenue window, 24x multiplier)
- `channel_utilization_distribution_1s.txt` - Utilization analysis (1 second HTLC resolution)
- `channel_utilization_distribution_60s.txt` - Utilization analysis (60 second HTLC resolution)
