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
Clone the git repository of carlaKC/ln-data using
`git clone https://github.com/carlaKC/ln-data/`

Run these instructions from inside of the channel-utilization dir:
`cd channel-utilization`

Make sure that the script is executable:
`chmod +x channel-utilization.sh`

Run the script:
`./channel_utilization.sh`

The data will be exported in `fowarding_data.csv`, with timestamps and 
channel ids randomized to protect the privacy of the collecting node.

### ADDENDUM for a very large database with >1M entries
In case the pull request via circuitbreaker API does not work because of very large database, 
copy the database of circuitbreaker to the directory channel-utilization.

Example of copy command dependent where circuitbreaker.db and the directory channel-utilization is located:
`cp /home/circuitbreaker/.circuitbreaker/circuitbreaker.db /home/admin/ln-data/channel-utilization/.`
 
Counting the amount of stored entries for information purposes:
`sqlite3 circuitbreaker.db "Select count(*) from forwarding_history;"`

Checking the integrity of the database:
`sqlite3 circuitbreaker.db "PRAGMA integrity_check;"`

If the db integrity is okay, `channel_utilization_sqlite.sh` which will extract the data using sqlite3 and export it to `fowarding_data.csv`. The script will make use of `../forwarding-history/randomize-data-fast.sh` for faster randomization. Run the script:
`./channel_utilization_sqlite.sh`
