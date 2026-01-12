#!/bin/bash

set -e

if [ $# -lt 3 ]; then
    echo "Please specify arguments as follows: $0 rpcserver macaroonpath tlscertpath [output]"
    exit 1
fi

rpcserver=$1
macaroonpath=$2
tlscertpath=$3

# Set default output if not provided
if [ $# -lt 4 ]; then
    output="channel_capacities.csv"
else
    output=$4
fi

if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed. Please install jq first."
    exit 1
fi

echo "short_channel_id,capacity,max_accepted_htlcs" > "$output"

echo "Fetching active channels..."
lncli --rpcserver="$rpcserver" --macaroonpath="$macaroonpath" --tlscertpath="$tlscertpath" listchannels | jq -r '.channels[] | select(.scid != null and .scid != "0") | [.scid, .capacity, .local_constraints.max_accepted_htlcs] | @csv' >> "$output"

echo "Fetching closed channels..."
lncli --rpcserver="$rpcserver" --macaroonpath="$macaroonpath" --tlscertpath="$tlscertpath" closedchannels | jq -r '.channels[] | select(.scid != null and .scid != "0") | [.scid, .capacity, 483] | @csv' >> "$output"

# Count total channels
TOTAL=$(tail -n +2 "$output" | wc -l | tr -d ' ')
echo "Wrote $TOTAL channels to $output"
