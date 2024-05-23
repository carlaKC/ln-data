#!/bin/bash

# Define the output CSV file
output_file="forwarding_data_without_randomization.csv"

# Perform integrity check on the SQLite database
db_file="circuitbreaker.db"
echo -n "Checking integrity of $db_file....."
integrity_check=$(sqlite3 $db_file "PRAGMA integrity_check;")
if [ "$integrity_check" != "ok" ]; then
  echo "failed. Please stop circuitbreaker before copying db"
  exit 1
else
  echo "ok"
fi

# Create CSV header
echo "add_time_ns,resolved_time_ns,chan_id_in,chan_id_out,amt_in_msat,amt_out_msat,fee_msat" > "$output_file"

# Initialize counter
counter=0
batch_size=100000

# Function to process a batch of data
process_batch() {
    local offset=$1
    sqlite3 -csv -noheader circuitbreaker.db <<EOF
SELECT add_time, resolved_time, incoming_channel, outgoing_channel, incoming_amt_msat, outgoing_amt_msat,
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
    echo "Processed $counter entries"

    # Increment offset for the next batch
    offset=$((offset + batch_size))
done

echo "Temporary CSV file created successfully: $output_file, now pseudo-randomizing channel_ids"
./randomize-data-fast.sh "$output_file"

#rm "$output_file"
echo "Channel IDs of forwarding history now randomized, final data available in forwarding_data.csv"
