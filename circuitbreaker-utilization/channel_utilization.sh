#!/bin/bash


# Define the output CSV file
output_file="temp.csv"

# Fetch JSON data from the API
json_data=$(wget -qO- http://localhost:9235/api/forwarding_history)

# Check if wget was successful
if [ $? -ne 0 ]; then
  echo "Failed to fetch data from API"
  exit 1
fi

# Create CSV header
echo "add_time_ns, resolve_time_ns, chan_id_in, chan_id_out, amt_in_msat, amt_out_msat, fee_msat" > "$output_file"

echo "$json_data" | jq -r '
  .forwards[] | [
    .addTimeNs,
	.resolveTimeNs,
    .incomingCircuit.shortChannelId,
    .outgoingCircuit.shortChannelId,
    .incomingAmount,
    .outgoingAmount,
	(.incomingAmount | tonumber ) - (.outgoingAmount | tonumber )
  ] | @csv
' >> "$output_file"

# Check if jq was successful
if [ $? -ne 0 ]; then
  echo "Failed to parse JSON data"
  exit 1
fi

echo "Temporary CSV file created successfully: $output_file, randomizing data"
./randomize-data.sh "$output_file"

rm "$output_file"
echo "Randomized forwarding history, final data available in forwarding_data.csv"
