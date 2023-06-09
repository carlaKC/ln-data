#!/bin/bash

# Check if the CSV file location is provided
if [ -z "$1" ]; then
  echo "Error: Please provide the CSV file location as an argument."
  exit 1
fi

# Read the CSV file
csv_file="$1"

# Validate if the file exists
if [ ! -f "$csv_file" ]; then
  echo "Error: File '$csv_file' not found."
  exit 1
fi

# Associative array to cache random values for chan_id_in and chan_id_out
declare -a random_values_cache

# Function to generate random value
generate_random_value() {
  local value
  value=$(shuf -i 100000000000000-999999999999999 -n 1)
  echo "$value"
}

# Process the CSV file and write to new CSV file
output_file="forwarding_data.csv"

echo "timestamp_ns, chan_id_in, chan_id_out, amt_in_msat, amt_out_msat, fee_msat" > "$output_file"
while IFS=',' read -r timestamp_ns chan_id_in chan_id_out amt_in_msat amt_out_msat fee_msat; do
  # Remove leading/trailing double quotes if present
  timestamp_ns="${timestamp_ns//\"/}"
  amt_in_msat="${amt_in_msat//\"/}"
  amt_out_msat="${amt_out_msat//\"/}"
  chan_id_in="${chan_id_in//\"/}"
  chan_id_out="${chan_id_out//\"/}"
  fee_msat="${fee_msat//\"/}"

  # Generate or retrieve random values for chan_id_in and chan_id_out
  if [[ -z "${random_values_cache[$chan_id_in]}" ]]; then
    random_values_cache[$chan_id_in]=$(generate_random_value)
  fi
  random_id_in="${random_values_cache[$chan_id_in]}"

  if [[ -z "${random_values_cache[$chan_id_out]}" ]]; then
    random_values_cache[$chan_id_out]=$(generate_random_value)
  fi
  random_id_out="${random_values_cache[$chan_id_out]}"

  # Write the parsed values with random chan_id_in and chan_id_out to the new CSV file
  echo "$timestamp_ns, $random_id_in, $random_id_out, $amt_in_msat, $amt_out_msat, $fee_msat" >> "$output_file"
done < <(tail -n +2 "$csv_file")

echo "Parsing complete. Results written to $output_file"
