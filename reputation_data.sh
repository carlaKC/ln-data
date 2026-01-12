#!/bin/bash

set -e

# Detect Python command
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
else
    echo "Error: Python is not installed. Please install Python 3 and try again."
    exit 1
fi

# Check if required arguments are provided
if [ $# -lt 3 ]; then
    echo "Usage: $0 rpcserver macaroonpath tlscertpath [sleep_seconds] [start_time_unix_seconds]"
    exit 1
fi

# Store command line arguments
rpcserver=$1
macaroonpath=$2
tlscertpath=$3

# Optional sleep seconds (default: empty)
sleep_seconds=""
if [ $# -ge 4 ]; then
    sleep_seconds=$4
fi

# Optional start time (default: 1704067200 - Jan 1, 2024)
start_time=""
if [ $# -ge 5 ]; then
    start_time=$5
fi

echo "==================================="
echo "Starting data collection pipeline"
echo "==================================="

# Create results directory
mkdir -p results

# Step 1: Run HTLC resolution
echo ""
echo "Step 1/5: Processing HTLC resolution from logs..."
if [ ! -d "htlc-resolution/logs" ] || [ -z "$(ls -A htlc-resolution/logs/*.log* 2>/dev/null)" ]; then
    echo "Error: No logs found in htlc-resolution/logs/"
    echo ""
    echo "Please copy your LND logs before running this script:"
    echo "  cp -r /path/to/.lnd/logs/bitcoin/mainnet/*.log* htlc-resolution/logs/"
    echo ""
    exit 1
fi

cd htlc-resolution
$PYTHON_CMD parse_htlc_logs.py logs ../results/htlc_resolution_distribution.txt
cd ..

# Step 2: Pull forwarding history
echo ""
echo "Step 2/5: Collecting forwarding history..."
cd forwarding-history
if [ -n "$sleep_seconds" ] && [ -n "$start_time" ]; then
    ./lnd-forwarding-history.sh "$rpcserver" "$macaroonpath" "$tlscertpath" "$sleep_seconds" "$start_time"
elif [ -n "$sleep_seconds" ]; then
    ./lnd-forwarding-history.sh "$rpcserver" "$macaroonpath" "$tlscertpath" "$sleep_seconds"
else
    ./lnd-forwarding-history.sh "$rpcserver" "$macaroonpath" "$tlscertpath"
fi
cd ..

# Step 3: Pull channel capacities
echo ""
echo "Step 3/5: Collecting channel capacities..."
cd channel-capacity
./channel_capacities.sh "$rpcserver" "$macaroonpath" "$tlscertpath"
cd ..

# Step 4: Run channel reputation (multiple configurations)
echo ""
echo "Step 4/5: Computing channel reputation scores..."
cd channel-reputation

# 2 weeks revenue window, 12 multiplier
$PYTHON_CMD reputation.py --input-csv-file ../forwarding-history/forwarding_events.csv --revenue-window-secs 1209600 --reputation-multiplier 12

# 4 weeks revenue window, 12 multiplier
$PYTHON_CMD reputation.py --input-csv-file ../forwarding-history/forwarding_events.csv --revenue-window-secs 2419200 --reputation-multiplier 12

# 2 weeks revenue window, 24 multiplier
$PYTHON_CMD reputation.py --input-csv-file ../forwarding-history/forwarding_events.csv --revenue-window-secs 1209600 --reputation-multiplier 24

# Move all generated files to results directory
mv channel_scores_*days_*days.csv ../results/ 2>/dev/null || true
cd ..

# Step 5: Calculate channel utilization distribution (multiple resolution times)
echo ""
echo "Step 5/5: Calculating channel utilization distribution..."
cd utilization

# 1 second HTLC resolution time
echo "  - Calculating with 1 second HTLC resolution time..."
$PYTHON_CMD calculate_utilization.py ../forwarding-history/forwarding_events.csv ../channel-capacity/channel_capacities.csv --htlc-resolution-time 1

# 60 second HTLC resolution time
echo "  - Calculating with 60 second HTLC resolution time..."
$PYTHON_CMD calculate_utilization.py ../forwarding-history/forwarding_events.csv ../channel-capacity/channel_capacities.csv --htlc-resolution-time 60

# Move all generated files to results directory
mv channel_utilization_distribution_*.txt ../results/ 2>/dev/null || true
cd ..

echo ""
echo "==================================="
echo "Data collection complete!"
echo "==================================="
echo ""
echo "Results generated:"
echo "  - forwarding-history/forwarding_events.csv"
echo "  - channel-capacity/channel_capacities.csv"
echo "  - results/htlc_resolution_distribution.txt"
echo "  - results/channel_scores_*days_*days.csv"
echo "  - results/channel_utilization_distribution_1s.txt"
echo "  - results/channel_utilization_distribution_60s.txt"
echo ""
echo "Please send us the files in the results directory!"
