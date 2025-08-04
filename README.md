# Solana Stake Pools Checker

A powerful and flexible bash script for Solana validators and researchers to check and analyze the composition of stake accounts delegating to any validator. This tool categorizes stake based on known stake pools, groups, and categories, providing clear, aggregated insights directly in your terminal or in a machine-readable JSON format.

This script helps you understand exactly who is staking to your validator - whether it's liquid staking pools like Marinade and Jito, investment funds, or individual stakers - and agregate this stakes or save its history.

**Author: CryptoVik Validator** : [Website](https://cryptovik.info) / [Github](https://github.com/SOFZP) / [Stakewiz](https://stakewiz.com/validator/Fhks5gukimP6vxKYbRY4V1aw888EgHhpdDSscD9V6bub)
<br>
**Follow me on X:** [@hvzp3](https://x.com/hvzp3)
<br>
**Support me:** Please support my work by staking to the **"CryptoVik"** validator on Solana.

---

### **Example of Text Output**


*Text Output Example: Pool, Group, Category modes for different validators, sorted by active stakes:*

![Text Output Example: Pool, Group, Category modes](https://raw.githubusercontent.com/SOFZP/Solana-Stake-Pools-Checker/refs/heads/main/stakepools-checker-demo1.png)

---

## Features

* **Validator Agnostic:** Check the stake distribution for **any** validator on the network, not just your own.
* **Multiple Aggregation Levels:** Group results by individual stake **pool**, broader **group** (e.g., "All Marinade, all SFDP etc"), or high-level **category** (e.g., "Delegation Programs, Paid Stakepools etc").
* **Flexible Sorting:** Sort the output based on multiple criteria, such as active stake amount, stake count, or name, in both ascending and descending order.
* **Dual Output Modes:**
    * **Human-Readable Text:** Colorized, formatted text output for quick analysis in the terminal.
    * **JSON Format:** Detailed and structured JSON output for integration with other scripts, dashboards, or data analysis pipelines.
* **Dynamic Data Source:** Automatically fetches and caches the latest list of stake pools from the [Solana Stake Pools Research](https://github.com/SOFZP/Solana-Stake-Pools-Research) repository.
* **Network Flexibility:** Works with `mainnet-beta`, `testnet`, `devnet`, or any custom RPC endpoint.
* **Zero Configuration Needed:** Automatically detects your local Solana CLI configuration for validator identity and network, but allows overriding everything with command-line flags.

## Data Source

The heart of this checker is its ability to classify stake accounts. The classification data (pool names, authorities, types, groups, etc.) is sourced directly from the community-driven project:

➡️ **[Solana Stake Pools Research](https://github.com/SOFZP/Solana-Stake-Pools-Research)**

The script uses the `stakepools_list.csv` file from that repository:
➡️ **[View the CSV file here](https://github.com/SOFZP/Solana-Stake-Pools-Research/blob/main/stakepools_list.csv)**

This external data source ensures that as new pools are identified and categorized, the script will automatically benefit from the updates.

## Prerequisites

Before using the script, ensure you have the following command-line tools installed:

* **`solana-cli`**: The official Solana Command Line Interface.
* **`jq`**: A lightweight and flexible command-line JSON processor.
* **`bc`**: An arbitrary precision calculator language (used for calculations).
* **`curl`**: A tool to transfer data from or to a server.
* **`perl`** or **`awk`**: For reliable CSV parsing.

## Installation

1.  Clone the repository or download the `stakepools-checker.sh` script.
    ```git clone https://github.com/SOFZP/Solana-Stake-Pools-Checker.git```
    ```cd Solana-Stake-Pools-Checker```

2.  Make the script executable:
    ```chmod +x stakepools-checker.sh```

## Usage

The script is run from the command line. You can run it without any arguments to check the validator identity configured in your local Solana CLI.

```./stakepools-checker.sh [OPTIONS] [SORT_CRITERIA...]```

### Options

| Flag                        | Description                                                                                              |
| --------------------------- | -------------------------------------------------------------------------------------------------------- |
| <code>-h, --help</code>     | Display the help message and exit.                                                                       |
| <code>-i, --identity <PUBKEY></code> | Specify the validator identity public key to check. Defaults to your local Solana address.               |
| <code>-u, --url <CLUSTER></code> | Specify Solana cluster (`mainnet-beta`, `testnet`, `devnet`) or a custom RPC URL.                        |
| <code>--output <json></code>  | Output data in valid JSON format.                                                                        |
| <code>-p, --by-pool</code>    | Aggregate results by stake pool (this is the default behavior).                                          |
| <code>-g, --by-group</code>   | Aggregate results by the predefined group (e.g., `Liquid Staking`).                                      |
| <code>-c, --by-category</code>| Aggregate results by the predefined category (e.g., `Public Pool`).                                      |

### Sorting (Text Output Only)

You can specify one or more sorting criteria. The format is `COLUMN_NUMBER:ORDER`. For example, `5:DESC` sorts by active stake in descending order.

1.  **KEY_AUTHORITY / NAME** (string sort)
2.  **COUNT** (numeric sort, e.g., `2:DESC`)
3.  **INFO** (string sort)
4.  **PERCENT** (numeric sort)
5.  **ACTIVE** stake (numeric sort, e.g., `5:DESC`)
6.  **DEACTIVATING** stake (numeric sort)
7.  **ACTIVATING** stake (numeric sort)

## Examples

### 1. Default Check

Check the validator configured in your local Solana CLI, aggregated by pool, and sorted by active stake descending.

```./stakepools-checker.sh```

### 2. Check a Specific Validator and Sort

Check a specific validator (`7d2m...`), aggregate by pool, and sort by Active Stake (descending), then by Stake Count (descending).

```./stakepools-checker.sh -i 7d2m1D5h6... 5:DESC 2:DESC```

### 3. Aggregate by Group

Check your validator but aggregate the results by the broader "group" definition.

```./stakepools-checker.sh --by-group```

### 4. JSON Output

Get the full, detailed data in JSON format. This is perfect for feeding into other applications.

```./stakepools-checker.sh -i 7d2m1D5h6... --output json```

For a more readable view, pipe the JSON output to `jq`:

```./stakepools-checker.sh -i 7d2m1D5h6... --output json | jq .```


*JSON Output Example of `./stakepools-checker.sh --output json | jq .` saved in file. Some fields are collapsed:*

![JSON Output Example of ./stakepools-checker.sh --output json | jq . saved in file. Some fields are collapsed](https://github.com/SOFZP/Solana-Stake-Pools-Checker/blob/main/stakepools-checker-demo3.png?raw=true)

### JSON Output Structure

The JSON output is a single, comprehensive object containing:

* **`metadata`**: General information like timestamp, epoch, and cluster name.
* **`pool_definitions`**: The complete list of all known pools from the source CSV.
* **`validators`**: An array containing the data for the checked validator.
    * **`info`**: Validator identity, vote pubkey, and name.
    * **`totals`**: Wide totals for stake accounts, active/activating/deactivating lamports for this validator.
    * **`aggregations`**: Objects containing the results grouped `by_pool`, `by_group`, and `by_category`.
    * **`other_stake_account_keys`**: A list of stake account public keys that could not be matched to any known pool.
* **`script_info`**: Metadata about the script's execution time.

---

<div align="center">
  <p>Made with ❤️ for the Solana community.</p>
  <p><strong>Stand with Ukraine 🇺🇦</strong></p>
</div>
