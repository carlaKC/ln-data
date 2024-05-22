# Channel Utilization Data

These instructions export forwarding data that has been collected in 
circuitbreaker.

There are two phases in this data collection: 
1. Pull data from circuitbreaker
2. Randomization of data to remove sensitive information

Responses are parsed using [jq](https://jqlang.github.io/jq/) - please 
open an issue if this requirement is not possible in your production 
environment!

## Run instructions

Run these instructions from inside of the channel-utilization dir:
`cd channel-utilization`

Make sure that the script is executable:
`chmod +x channel-utilization.sh`

Run the script:
`./channel_utilization.sh`

The data will be exported in `fowarding_data.csv`, with timestamps and 
channel ids randomized to protect the privacy of the collecting node.
