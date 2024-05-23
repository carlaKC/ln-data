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

# Temporary file to store random values
random_values_file=$(mktemp)

# Write header to the output file
echo "timestamp_ns,chan_id_in,chan_id_out,amt_in_msat,amt_out_msat,fee_msat" > "$output_file"

# Number of random values to pre-generate
random_pool_size=1000000

# Function to generate random values and append to the temporary file
generate_random_pool() {
  shuf -i 100000000000000000-999999999999999999 -n $random_pool_size >> "$random_values_file"
}

# Generate initial pool of random values
generate_random_pool

# Use awk to process the CSV file
awk -F, -v output_file="$output_file" -v random_values_file="$random_values_file" -v random_pool_size="$random_pool_size" '
BEGIN {
  counter = 0
  rv_idx = 0
  random_value_count = 0
  while ((getline < random_values_file) > 0) {
    random_values[random_value_count++] = $0
  }
  close(random_values_file)
}
function get_next_random() {
  if (rv_idx >= random_value_count) {
    # If we run out of random values, generate more and reload them
    cmd = "shuf -i 100000000000000000-999999999999999999 -n " random_pool_size
    while ((cmd | getline value) > 0) {
      random_values[rv_idx++] = value
    }
    close(cmd)
    rv_idx = 0
  }
  return random_values[rv_idx++]
}
NR > 1 {
  # Remove leading/trailing double quotes if present
  gsub(/^"|"$/, "", $1)
  gsub(/^"|"$/, "", $2)
  gsub(/^"|"$/, "", $3)
  gsub(/^"|"$/, "", $4)
  gsub(/^"|"$/, "", $5)
  gsub(/^"|"$/, "", $6)

  # Use pre-generated random values
  random_id_in = get_next_random()
  random_id_out = get_next_random()

  # Write the parsed values with random chan_id_in and chan_id_out to the new CSV file
  printf "%s,%s,%s,%s,%s,%s\n", $1, random_id_in, random_id_out, $4, $5, $6 >> output_file

  # Increment and print the counter
  counter++
  if (counter % 100000 == 0) {
    print "Randomized " counter " rows" > "/dev/stderr"
  }
}
' "$csv_file"

# Clean up
rm "$random_values_file"

echo "Parsing complete. Results written to $output_file"
