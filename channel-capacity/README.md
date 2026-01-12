## Channel Capacities

These instructions export the channel capacity data from a lightning node.
The final product is `channel_capacities.csv` which contains the
short_channel_id, capacity, and max_accepted_htlcs for both active and
closed channels on the node.

The script collects the channel capacity and in flight htlc limits for
all of the node's channels. Note that pending channels are not included,
only channels that have been fully opened and closed are (due to data
availability in LND's API).

*Note that channel ids are not randomized*.

Responses are parsed using [jq](https://jqlang.github.io/jq/) - please
open an issue if this requirement is not possible in your production
environment!

### Run Instructions
Requirements: access to lnd's [ListChannels](https://lightning.engineering/api-docs/api/lnd/lightning/list-channels)
and [ClosedChannels](https://lightning.engineering/api-docs/api/lnd/lightning/closed-channels) APIs,
read only macaroon, `lncli` and [jq](https://jqlang.github.io/jq/).

Ensure that the script is executable:
```
chmod +x channel_capacities.sh
```

Run `channel_capacities.sh` with the following arguments:
`./channel-capacities/channel_capacities.sh rpcserver macaroonpath tlscertpath [output]`

Example:
```
./channel_capacities.sh localhost:10009 ~/.lnd/data/chain/bitcoin/mainnet/readonly.macaroon ~/.lnd/tls.cert
```

The script will create a CSV file with the following structure:
```
short_channel_id,capacity,max_accepted_htlcs
"124244814004224","15000000",483
```
