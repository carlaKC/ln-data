#!/bin/bash

# Execute lnd-forwarding-history.sh with provided arguments
./lnd-forwarding-history.sh "$@"

# Check the exit code of lnd-forwarding-history.sh
if [ $? -ne 0 ]; then
  echo "lnd-forwarding-history.sh failed. Exiting."
  exit 1
fi

# Execute randomize-data.sh with the generated forwarding_events.csv
./randomize-data.sh forwarding_events.csv

# Check the exit code of randomize-data.sh
if [ $? -ne 0 ]; then
  echo "randomize-data.sh failed. Exiting."
  exit 1
fi

# Clean up the data with actual channel IDs so that users don't accidentally leak their own data.
rm forwarding_events.csv

echo "Script execution completed successfully - see forwarding_data.csv for forwarding history with randomized channel IDs."
