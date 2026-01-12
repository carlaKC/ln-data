## HTLC Resolution Times

This script will examine LND's logs for HTLC forwarding data and output
the distribution of HTLC forwarding resolution times.

This script requires that you make a copy of the LND logs in the `/logs`
directory, and that LND is running with `debuglevel=debug`.

## Run Instructions

1. Copy your LND logs to the `logs` directory:
   ```sh
   cp -r /path/to/.lnd/logs/bitcoin/mainnet/*.log* htlc-resolution/logs/
   ```

2. Run the script:
   ```sh
   python htlc-resolution/parse_htlc_logs.py
   ```

The results will be written to `htlc_resolution_distribution.txt` and
displayed on screen. You may optionally provide custom log and output
arguments using:
   ```sh
   python parse_htlc_logs.py {log_dir} {output_file}
   ```

A bash version (`parse_htlc_logs.sh`) is also available if preferred.

Note: out of an abundance of caution, we recommend copying logs out of
your production environment, rather than pointing this script to your
live `lnd_dir`.
