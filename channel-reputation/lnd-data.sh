#!/bin/bash

set -e

# Check if at least 3 arguments are provided (rpcserver, macaroonpath, tlscertpath)
if [ $# -lt 3 ]; then
    echo "Usage: $0 rpcserver macaroonpath tlscertpath [sleep] [start_time]"
    echo ""
    echo "Arguments:"
    echo "  rpcserver     - LND RPC server address"
    echo "  macaroonpath  - Path to macaroon file"
    echo "  tlscertpath   - Path to TLS certificate"
    echo "  sleep         - Optional: Enable sleep between API calls (true/false)"
    echo "  start_time    - Optional: Unix timestamp to start from"
    exit 1
fi

# Store the current directory to know where to place files
CURRENT_DIR=$(pwd)

# Define intermediate file names
FORWARDING_DATA="forwarding_data.csv"
CHANNEL_CAPACITIES="channel_capacities.csv"
OUTPUT_SCORES="channel_scores.csv"

echo "=== Step 1: Fetching forwarding history ==="
# Run lnd-data.sh from the forwarding-history directory, but output to current dir
cd ../forwarding-history
./lnd-data.sh "$@"

# Move the output file to the current directory
mv "$FORWARDING_DATA" "$CURRENT_DIR/"
cd "$CURRENT_DIR"

echo ""
echo "=== Step 2: Fetching channel capacities ==="
# Run channel_capacities.sh from the channel-capacity directory
cd ../channel-capacity
./channel_capacities.sh "$1" "$2" "$3" "$CURRENT_DIR/$CHANNEL_CAPACITIES"
cd "$CURRENT_DIR"

echo ""
echo "=== Step 3: Calculating channel reputation ==="
# Run reputation.py with the intermediate files
python3 ./reputation.py "$FORWARDING_DATA" "$CHANNEL_CAPACITIES" "$OUTPUT_SCORES"

echo ""
echo "=== Step 4: Cleaning up intermediate files ==="
# Delete intermediate files
rm -f "$FORWARDING_DATA"
rm -f "$CHANNEL_CAPACITIES"

echo ""
echo "✓ Reputation calculation complete!"
echo "  Results saved to: $OUTPUT_SCORES"
