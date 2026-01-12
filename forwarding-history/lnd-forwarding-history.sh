#!/bin/bash

# Check if lncli binary exists
if ! command -v lncli &> /dev/null; then
    echo "lncli is not installed. Please install it and try again."
    exit 1
fi

# Check if jq command-line tool exists
if ! command -v jq &> /dev/null; then
    echo "jq is not installed. Please install it and try again."
    exit 1
fi

# Parse command line arguments
if [ $# -lt 3 ]; then
    echo "Please specify arguments as follows: $0 rpcserver macaroonpath tlscertpath [sleep] [start_time]"
    exit 1
fi

# Store command line arguments
rpcserver=$1
macaroonpath=$2
tlscertpath=$3

# Set default sleep value if not provided
if [ $# -lt 4 ]; then
    sleep_enabled=false
else
    sleep_enabled=$4
fi

# Set sleep duration based on the sleep_enabled flag
if [ "$sleep_enabled" = true ]; then
    sleep_duration=1
else
    sleep_duration=0
fi

# Set default start_time if not provided
if [ $# -lt 5 ]; then
    start_time=1704067200
else
    start_time=$5
fi

# Set initial values for pagination
index_offset=0
max_events=50000
total_events=0

# CSV file name
csv_file="forwarding_events.csv"

# Create or truncate the CSV file
echo "timestamp_ns,chan_id_in,chan_id_out,amt_in_msat,amt_out_msat,fee_msat" > "$csv_file"

# Loop until all forwarding events are retrieved
while true; do
    # Call lncli with the provided arguments and pagination parameters, capture output
    response=$(lncli \
        --rpcserver="$rpcserver" \
        --macaroonpath="$macaroonpath" \
        --tlscertpath="$tlscertpath" \
        fwdinghistory \
        --start_time="$start_time" \
        --index_offset="$index_offset" \
        --max_events="$max_events" \
        --skip_peer_alias_lookup)

    # Extract the forwarding events and last offset index from the response
    forwarding_events=$(echo "$response" | jq -r '.forwarding_events')
    last_offset_index=$(echo "$response" | jq -r '.last_offset_index')

    # Process and append forwarding events to the CSV file
    echo "$forwarding_events" | jq -r '.[] | [.timestamp_ns, .chan_id_in, .chan_id_out, .amt_in_msat, .amt_out_msat, .fee_msat] | @csv' >> "$csv_file"

    # Increment the total number of events
    total_events=$((total_events + $(echo "$forwarding_events" | jq -r 'length')))
	
	# Log the current number of events and index offset
    echo "Events retrieved: $total_events, offset: $index_offset"
	
    # Check if all events have been retrieved
    if [ $(echo "$forwarding_events" | jq -r 'length') -lt "$max_events" ]; then
        break
    fi

    # Update the index offset for the next query
    index_offset="$last_offset_index"

    # Add a short backoff to allow other calls to query the database
    sleep "$sleep_duration"
done

echo "Total events retrieved: $total_events"
echo "CSV file saved as: $csv_file"
