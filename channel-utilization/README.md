# Channel Utilization Data

These instructions will help you export forwarding data that has been collected in circuitbreaker.

There are two phases in this data collection:
1. Pull data from circuitbreaker.
2. Randomize the data to remove sensitive information.

Responses are parsed using [jq](https://jqlang.github.io/jq/). Please open an issue if this requirement is not possible in your production environment!

## Run Instructions

1. Clone the git repository of carlaKC/ln-data using:
   ```sh
   git clone https://github.com/carlaKC/ln-data/
   ```

2. Navigate to the channel-utilization directory:
   ```sh
   cd ln-data/channel-utilization
   ```

3. Run the script:
   ```sh
   bash channel_utilization.sh
   ```

The data will be exported in `forwarding_data.csv`, with timestamps and channel IDs randomized to protect the privacy of the collecting node.

### Addendum for Processing Very Large Circuitbreaker Database with >1M Entries

In case the pull request via the circuitbreaker API does not work because of too many entries or broken database, follow these steps:

1. Copy the circuitbreaker database to the `channel-utilization` directory.

   Example of a copy command depending on where `circuitbreaker.db` and the `channel-utilization` directory are located:
   ```sh
   cp /path/to/circuitbreaker.db /path/to/channel-utilization/.
   ```
   On MacOS you find circuitbreaker.db in
   `~/Library/Application\ Support/Circuitbreaker/circuitbreaker.db`

3. Count the number of stored entries for information purposes:
   ```sh
   sqlite3 circuitbreaker.db "SELECT count(*) FROM forwarding_history;"
   ```
   
4. Check the integrity of the circuitbreaker database:
   ```sh
   sqlite3 circuitbreaker.db "PRAGMA integrity_check;"
   ```
   
5. Run the alternative extraction script:
   ```sh
   bash channel_utilization_sqlite.sh
   ```

If the database integrity is okay, the script will extract the circuitbreaker data using `sqlite3` and export it to `forwarding_data.csv`. The script will make use of `randomize-data-fast.sh` for faster channel ID randomization. A lookup file of original to pseudo-random channel IDs is stored in `channel_id_mapping.csv`.

### Summary of Commands

1. Clone the repository:
   ```sh
   git clone https://github.com/carlaKC/ln-data/
   ```

2. Navigate to the directory:
   ```sh
   cd ln-data/channel-utilization
   ```

3. Run the script:
   ```sh
   bash channel_utilization.sh
   ```

4. In case of problems due to large circuitbreaker database:
   ```sh
   cp /path/to/circuitbreaker.db /path/to/channel-utilization/.
   bash channel_utilization_sqlite.sh
   ```
