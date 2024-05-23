#!/bin/bash

# Define the output CSV file
output_file="temp.csv"

# Create CSV header
echo "timestamp_ns,chan_id_in,chan_id_out,amt_in_msat,amt_out_msat,fee_msat" > "$output_file"

# Initialize counter
counter=0
batch_size=10000

# Function to process a batch of data
process_batch() {
    local offset=$1
    sqlite3 -csv -noheader circuitbreaker.db <<EOF
SELECT add_time, incoming_channel, outgoing_channel, incoming_amt_msat, outgoing_amt_msat,
(incoming_amt_msat - outgoing_amt_msat) AS fee_msat
FROM forwarding_history
LIMIT $batch_size OFFSET $offset;
EOF
}

# Process data in batches
offset=0
while true; do
    # Process a batch of data and append to CSV
    batch_data=$(process_batch $offset)

    # Break the loop if no more data is returned
    if [ -z "$batch_data" ]; then
        break
    fi

    # Increment counter
    counter=$((counter + batch_size))

    # Append batch data to CSV
    echo "$batch_data" >> "$output_file"

    # Output status message
    echo "Processed $counter rows"

    # Increment offset for the next batch
    offset=$((offset + batch_size))
done

echo "Temporary CSV file created successfully: $output_file, randomizing data"
../forwarding-history/randomize-data-fast.sh "$output_file"

#rm "$output_file"
echo "Randomized forwarding history, final data available in forwarding_data.csv"
