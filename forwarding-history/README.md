## Forwarding History

These instructions export the forwarding history of a LND node.
The final product is `forwarding_data.csv` which contains the timestamp,
amount, fee and incoming/outgoing channel for HTLCs forwarded by the 
node.

By default, this script will collect data from 1 January 2024. If you
would like to decrease this range, see the optional `start_time` 
parameter that is provided in the instructions below.

Responses are parsed using [jq](https://jqlang.github.io/jq/) - please 
open an issue if this requirement is not possible in your production 
environment!

### Run Instructions
Requirements: access to lnd's [ForwardingHistory API](https://lightning.engineering/api-docs/api/lnd/lightning/forwarding-history), 
read only macaroon, lncli and [jq](https://jqlang.github.io/jq/).

Ensure that all scripts are executable:
```
chmod +x ./forwarding-history/lnd-forwarding-history.sh
```

`./forwarding-history/lnd-forwarding-history.sh rpcserver macaroonpath tlscertpath [sleep] [start_time]`

#### Performance considerations
If your node is running with bbolt (the default database in LND) and 
you have a large volume forwards, you may want to consider setting the 
optional sleep parameter. This will instruct the data collection to 
back off for 1 second in between reads. This will give other node 
operations ample time to access the database, and limit the database 
load.
