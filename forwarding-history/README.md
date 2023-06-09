## Forwarding History

These instructions export and pseudonymize the forwarding history of a 
lightning node. The final product is `forwarding_events.csv` which 
contains the timestamp, amount, fee and obfuscated incoming/outgoing 
channel for HTLCs forwarded by the node.

By default, this script will collect data from 1 January 2023. If you
would like to decrease this range, see the optional `start_time` 
parameter that is provided in the instructions below.

There are two phases in this data collection: 
1. Collection of forwarding events from node in a CSV
2. Pseudonymization of data to remove sensitive information

Responses are parsed using [jq](https://jqlang.github.io/jq/) - please 
open an issue if this requirement is not possible in your production 
environment!

### LND Instructions
Requirements: access to lnd's [ForwardingHistory API](https://lightning.engineering/api-docs/api/lnd/lightning/forwarding-history), 
read only macaroon, lncli and [jq](https://jqlang.github.io/jq/).

Ensure that all scripts are executable:
```
chmod +x lnd-data.sh
chmod +x lnd-forwarding-history.sh
chmod +x pseudonymize-data.sh
```

Run `lnd-data.sh` with the following arguments: 
`lnd-data.sh rpcserver macaroonpath tlscertpath [sleep] [start_time]`

#### Performance considerations
If your node is running with bbolt (the default database in LND) and 
you have a large volume forwards, you may want to consider setting the 
optional sleep parameter. This will instruct the data collection to 
back off for 1 second in between reads. This will give other node 
operations ample time to access the database, and limit the database 
load.
