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

# Output file
output_file="forwarding_data.csv"

# Lookup file to store mapping of original to pseudo-random channel IDs
lookup_file="channel_id_mapping.csv"

# Write header to the output file
echo "add_time_ns,resolved_time_ns,chan_id_in,chan_id_out,amt_in_msat,amt_out_msat,fee_msat" > "$output_file"
echo "original_id,pseudo_id" > "$lookup_file"

# Number of random values to pre-generate in each batch
random_pool_size=10000

# Function to generate random values and append to a temporary file
generate_random_pool() {
  shuf -i 100000000000000000-999999999999999999 -n $random_pool_size
}

# Generate initial pool of random values and store in a temporary file
random_values_file=$(mktemp)
generate_random_pool > "$random_values_file"

# Use awk to process the CSV file
awk -F, -v output_file="$output_file" -v random_pool_size="$random_pool_size" -v lookup_file="$lookup_file" -v random_values_file="$random_values_file" '
BEGIN {
  counter = 0
  rv_idx = 0
  random_value_count = 0
  split("", chan_id_in_map)
  split("", chan_id_out_map)

  # Read initial random values from the temporary file
  while ((getline value < random_values_file) > 0) {
    random_values[random_value_count++] = value
  }
  close(random_values_file)
}
function generate_random_pool() {
  delete random_values
  cmd = "shuf -i 100000000000000000-999999999999999999 -n " random_pool_size
  rv_idx = 0
  while ((cmd | getline value) > 0) {
    random_values[rv_idx++] = value
  }
  close(cmd)
}
function get_next_random() {
  if (rv_idx >= random_value_count) {
    generate_random_pool()
  }
  return random_values[rv_idx++]
}
function get_pseudo_id(id, id_map) {
  if (!(id in id_map)) {
    id_map[id] = get_next_random()
    # Write the mapping to the lookup file
    printf "%s,%s\n", id, id_map[id] >> lookup_file
  }
  return id_map[id]
}
NR > 1 {
  # Remove leading/trailing double quotes if present
  gsub(/^"|"$/, "", $1)
  gsub(/^"|"$/, "", $2)
  gsub(/^"|"$/, "", $3)
  gsub(/^"|"$/, "", $4)
  gsub(/^"|"$/, "", $5)
  gsub(/^"|"$/, "", $6)
  gsub(/^"|"$/, "", $7)

  # Get or generate pseudo-random values for chan_id_in and chan_id_out
  pseudo_id_in = get_pseudo_id($3, chan_id_in_map)
  pseudo_id_out = get_pseudo_id($4, chan_id_out_map)

  # Write the parsed values with pseudo-random chan_id_in and chan_id_out to the new CSV file
  printf "%s,%s,%s,%s,%s,%s,%s\n", $1, $2, pseudo_id_in, pseudo_id_out, $5, $6, $7 >> output_file

  # Increment and print the counter
  counter++
  if (counter % 100000 == 0) {
    print "Randomized " counter " entries" > "/dev/stderr"
  }
}
' "$csv_file"

# Clean up
rm "$random_values_file"

echo "Parsing complete. Results written to $output_file"
echo "Channel ID mappings written to $lookup_file"
