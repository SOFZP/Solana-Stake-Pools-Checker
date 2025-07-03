#!/bin/bash
# 
# STAKEPOOL BASH CHECKER BY CRYPTOVIK VALIDATOR
# https://cryptovik.info
# 
# SUPPORT ME BY STAKING TO "CryptoVik" solana validator
# 
# Or by giving this repo a star
# https://github.com/SOFZP/Solana-Stake-Pools-Checker
# 
# And follow me on X
# https://x.com/hvzp3
# 
# Stand with Ukraine 🇺🇦
#

### 🎨 COLORS ###
NOCOLOR='\033[0m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LIGHTGRAY='\033[0;37m'
LIGHTPURPLE='\033[1;35m'

### 🔁 RETRY HELPERS ###

# Try to get JSON-valid response with `jq empty`
retry_jq_json() {
    local cmd="$1"
    local max_attempts="${2:-5}"
    local attempt=1
    local output=""

    while (( attempt <= max_attempts )); do
        output=$(eval "$cmd" 2>/dev/null)
        if echo "$output" | jq empty 2>/dev/null; then
            echo "$output"
            return 0
        else
            echo -e "${YELLOW}Attempt $attempt/$max_attempts failed. Retrying...${NOCOLOR}"
            sleep 2
        fi
        ((attempt++))
    done

    echo -e "${RED}Failed to retrieve valid JSON after $max_attempts attempts.\nCommand: $cmd${NOCOLOR}" >&2
    return 1
}

# Try a command, return value or fallback
retry_command() {
    local cmd="$1"
    local max_attempts="${2:-5}"
    local default_value="${3:-"N/A"}"
    local show_errors="${4:-"yes"}"
    local attempt=1
    local output=""

    while (( attempt <= max_attempts )); do
        output=$(eval "$cmd" 2>/dev/null)
        if [[ -n "$output" ]]; then
            echo "$output"
            return 0
        elif [[ "$show_errors" == "yes" || "$show_errors" == "true" ]]; then
            echo -e "${YELLOW}Attempt $attempt/$max_attempts failed. Retrying...${NOCOLOR}" >&2
        fi
        sleep 3
        ((attempt++))
    done

    echo -e "${RED}Failed to execute command after $max_attempts attempts.\nCommand: $cmd${NOCOLOR}" >&2
    echo "$default_value"
    return 1
}

### 📥 INPUTS ###

DEFAULT_SOLANA_ADRESS=$(solana address)
DEFAULT_CLUSTER='-ul'

THIS_SOLANA_ADRESS="${1:-$DEFAULT_SOLANA_ADRESS}"
SOLANA_CLUSTER=" ${2:-$DEFAULT_CLUSTER} "
IS_SHORT="${3:-"false"}"

### 🌐 CLUSTER LOGIC ###

THIS_CONFIG_RPC=$(solana config get | grep "RPC URL:")
if [[ "${SOLANA_CLUSTER}" == " -ul " ]]; then
  [[ $THIS_CONFIG_RPC == *"testnet"* ]] && SOLANA_CLUSTER=" -ut "
  [[ $THIS_CONFIG_RPC == *"mainnet"* ]] && SOLANA_CLUSTER=" -um "
fi

case "$SOLANA_CLUSTER" in
  " -ut ") CLUSTER_NAME="(TESTNET)" ; CLUSTER_NAME_FOR_API="testnet" ;;
  " -um ") CLUSTER_NAME="(Mainnet)" ; CLUSTER_NAME_FOR_API="mainnet-beta" ;;
  *)       CLUSTER_NAME="(Local)"   ; CLUSTER_NAME_FOR_API="" ;;
esac

### 🧠 EPOCH INFO ###
EPOCH_INFO=$(retry_command "solana ${SOLANA_CLUSTER} epoch-info" 5 "null" false)
THIS_EPOCH=$(echo "$EPOCH_INFO" | grep 'Epoch:' | awk '{print $2}')
LAST_EPOCH="$THIS_EPOCH"

### 🔍 FIND VOTE ACCOUNT ###
SOLANA_VALIDATORS_JSON=$(retry_command "solana ${SOLANA_CLUSTER} validators --output json-compact" 10 "" false)
THIS_VALIDATOR_JSON=$(echo "$SOLANA_VALIDATORS_JSON" | jq --arg ID "$THIS_SOLANA_ADRESS" '.validators[] | select(.identityPubkey == $ID)')

# Retry to extract vote pubkey
MAX_RETRIES=10
RETRY_INTERVAL=2
YOUR_VOTE_ACCOUNT=""
for ((i=1; i<=MAX_RETRIES; i++)); do
    YOUR_VOTE_ACCOUNT=$(echo "$THIS_VALIDATOR_JSON" | jq -r '.voteAccountPubkey')
    [[ -n "$YOUR_VOTE_ACCOUNT" && "$YOUR_VOTE_ACCOUNT" != "null" ]] && break
    sleep $RETRY_INTERVAL
done
[[ -z "$YOUR_VOTE_ACCOUNT" || "$YOUR_VOTE_ACCOUNT" == "null" ]] && YOUR_VOTE_ACCOUNT=""

LAMPORTS_IN_SOL=1000000000

if [[ -z "$YOUR_VOTE_ACCOUNT" ]]; then
    echo -e "${RED}❌ Can't find vote account for identity: $THIS_SOLANA_ADRESS"
    echo -e "It may not exist, may use --no-voting, or an RPC error occurred.${NOCOLOR}"
    exit 1
fi

### 🔎 CORRECT LAST EPOCH FOR BOT ###
iterator=0
DONE_STOP=0
while (( DONE_STOP == 0 )); do
    KYC_API_VERCEL=$(retry_jq_json "curl -s 'https://api.solana.org/api/validators/epoch-stats?cluster=${CLUSTER_NAME_FOR_API}&epoch=${LAST_EPOCH}'")
    
    if [[ "$(echo "$KYC_API_VERCEL" | jq -r '.message')" != "null" ]]; then
        LAST_EPOCH=$(echo "$LAST_EPOCH - 1" | bc)
    else
        DONE_STOP=1
    fi

    ((iterator++))
    (( iterator >= 10 )) && DONE_STOP=1
done

LAST_BOT_EPOCH=$(echo "$KYC_API_VERCEL" | jq -r '.epoch')

### 🧾 LOAD VALIDATOR NAMES ###
VALIDATOR_NAMES_JSON=$(retry_command "solana ${SOLANA_CLUSTER} validator-info get --output json" 5 "null" false)
declare -A VALIDATOR_NAMES

while IFS=$'\t' read -r identity name; do
    [[ -z "$name" ]] && name="NO NAME"
    name=$(echo "$name" | sed 's/ /\\u00A0/g') # Non-breaking space
    VALIDATOR_NAMES["$identity"]="$name"
done < <(echo "$VALIDATOR_NAMES_JSON" | jq -r '.[] | "\(.identityPubkey)\t\(.info.name // "NO NAME")"')








### 🌐 Load Stake Pools List from GitHub TSV ###
load_stakepools_list() {
    local url="https://raw.githubusercontent.com/SOFZP/Solana-Stake-Pools-Research/main/stakepools_list.conf"
    local local_file="/tmp/stakepools_list.conf"

    # Download the TSV file from GitHub
    if ! curl -fsSL "$url" -o "$local_file"; then
        echo -e "${RED}❌ Failed to download stakepools_list.conf from GitHub${NOCOLOR}"
        return 1
    fi

    # Declare global associative arrays for lookup
    declare -gA POOL_KEYS_W     # key = withdraw pubkey, value = short name
    declare -gA POOL_KEYS_S     # key = stake pubkey, value = short name
    declare -gA POOL_LONG_NAME  # key = short name, value = long name
    declare -gA POOL_URL        # key = short name, value = dashboard URL

    # Read each line and populate the arrays
    while IFS=$'\t' read -r short_name type pubkey long_name url; do
        # Skip commented or empty lines
        [[ "$short_name" =~ ^#.*$ || -z "$pubkey" ]] && continue

        # Store withdraw or stake authority keys
        if [[ "$type" == "W" ]]; then
            POOL_KEYS_W["$pubkey"]="$short_name"
        elif [[ "$type" == "S" ]]; then
            POOL_KEYS_S["$pubkey"]="$short_name"
        fi

        # Store additional metadata
        POOL_LONG_NAME["$short_name"]="$long_name"
        POOL_URL["$short_name"]="$url"

    done < <(grep -v '^#' "$local_file")
}






### 🔍 Analyze stake pools delegating to a validator ###
analyze_validator_stake_pools() {
    local input_key="$1"
    local cluster="${2:-"-ul"}"

    # Auto-select cluster if -ul
    if [[ "$cluster" == "-ul" ]]; then
        local config_rpc=$(solana config get | grep "RPC URL:" | awk '{print $NF}')
        [[ "$config_rpc" == *"mainnet"* ]] && cluster="-um"
        [[ "$config_rpc" == *"testnet"* ]] && cluster="-ut"
    fi

    # Get vote account (if identity was passed)
    local validators_json=$(retry_command "solana $cluster validators --output json-compact" 5 "" false)
    local validator_json=$(echo "$validators_json" | jq --arg ID "$input_key" '.validators[] | select(.identityPubkey==$ID or .voteAccountPubkey==$ID)')
    local vote_account=$(echo "$validator_json" | jq -r '.voteAccountPubkey // empty')

    if [[ -z "$vote_account" || "$vote_account" == "null" ]]; then
        echo -e "${RED}❌ Can't find vote account for identity: $input_key${NOCOLOR}"
        return 1
    fi
    echo -e "${CYAN}Vote account detected: $vote_account${NOCOLOR}"

    # Get all stakes for this vote account
    local all_stakes=$(retry_command "solana $cluster stakes $vote_account" 5 "" false)

    # Extract stake/withdraw pairs
    mapfile -t stake_pairs < <(
        echo "$all_stakes" | grep -E -B1 "Withdraw Authority" |
        grep -oP "(?<=Stake Authority: ).*|(?<=Withdraw Authority: ).*" |
        paste -d '+' - - | sort -u
    )

    # Handle S-type pools separately
    mapfile -t all_stake_accounts < <(echo "$all_stakes" | grep -oP "(?<=Stake Account: )\w+")

    declare -A POOL_STATS_ACTIVE
    declare -A POOL_STATS_ACTIVATING
    declare -A POOL_STATS_DEACTIVATING

    for pair in "${stake_pairs[@]}"; do
        local stake_key="${pair%%+*}"
        local withdraw_key="${pair##*+}"
        local short_name=""

        if [[ -n "${POOL_KEYS_S[$stake_key]}" ]]; then
            short_name="${POOL_KEYS_S[$stake_key]}"
        elif [[ -n "${POOL_KEYS_W[$withdraw_key]}" ]]; then
            short_name="${POOL_KEYS_W[$withdraw_key]}"
        else
            continue
        fi

        local stake_block=$(echo "$all_stakes" | grep -B7 "$withdraw_key")

        local active=$(echo "$stake_block" | awk '/Active Stake:/ {gsub("Active Stake: ", "", $0); gsub(" SOL", "", $0); sum+=$1} END {printf "%.2f", sum}')
        local activating=$(echo "$stake_block" | awk '/Activating Stake:/ {gsub("Activating Stake: ", "", $0); gsub(" SOL", "", $0); sum+=$1} END {printf "%.2f", sum}')
        local deactivating=$(echo "$stake_block" | awk '
        {
          if (tolower($0) ~ /deactivates/ && prev ~ /Active Stake:/) {
            gsub("Active Stake: ", "", prev)
            gsub(" SOL", "", prev)
            sum += prev
          }
          prev = $0
        }
        END {printf "%.2f", sum}')

        POOL_STATS_ACTIVE["$short_name"]=$(echo "${POOL_STATS_ACTIVE[$short_name]:-0} + $active" | bc)
        POOL_STATS_ACTIVATING["$short_name"]=$(echo "${POOL_STATS_ACTIVATING[$short_name]:-0} + $activating" | bc)
        POOL_STATS_DEACTIVATING["$short_name"]=$(echo "${POOL_STATS_DEACTIVATING[$short_name]:-0} + $deactivating" | bc)
    done

    # Now handle S-type pools
    for acc in "${all_stake_accounts[@]}"; do
        local authority=$(solana $cluster account "$acc" --output json | jq -r '.data.parsed.info.meta.authorized.staker // empty')
        if [[ -n "$authority" && -n "${POOL_KEYS_S[$authority]}" ]]; then
            local short_name="${POOL_KEYS_S[$authority]}"
            local active=$(echo "$all_stakes" | grep -A6 "$acc" | awk '/Active Stake:/ {gsub("Active Stake: ", "", $0); gsub(" SOL", "", $0); print $1}' | paste -sd+ - | bc)
            local activating=$(echo "$all_stakes" | grep -A6 "$acc" | awk '/Activating Stake:/ {gsub("Activating Stake: ", "", $0); gsub(" SOL", "", $0); print $1}' | paste -sd+ - | bc)
            local deactivating=$(echo "$all_stakes" | grep -A6 "$acc" | awk '
              {
                if (tolower($0) ~ /deactivates/ && prev ~ /Active Stake:/) {
                  gsub("Active Stake: ", "", prev)
                  gsub(" SOL", "", prev)
                  print prev
                }
                prev = $0
              }' | paste -sd+ - | bc)

            [[ -n "$active" ]] && POOL_STATS_ACTIVE["$short_name"]=$(echo "${POOL_STATS_ACTIVE[$short_name]:-0} + $active" | bc)
            [[ -n "$activating" ]] && POOL_STATS_ACTIVATING["$short_name"]=$(echo "${POOL_STATS_ACTIVATING[$short_name]:-0} + $activating" | bc)
            [[ -n "$deactivating" ]] && POOL_STATS_DEACTIVATING["$short_name"]=$(echo "${POOL_STATS_DEACTIVATING[$short_name]:-0} + $deactivating" | bc)
        fi
    done

    # Sort pools by ACTIVE descending
    local sorted_pools=$(for pool in "${!POOL_STATS_ACTIVE[@]}"; do
        echo -e "${POOL_STATS_ACTIVE[$pool]}\t$pool"
    done | sort -nr | cut -f2)

    echo -e "\n${CYAN}Stake Pools Delegating to $vote_account:${NOCOLOR}"
    printf "${NOCOLOR}%-20s${NOCOLOR} %-12s %-12s %-12s\n" "STAKE_NAME" "ACTIVE" "ACTIVATING" "DEACTIVATING"

    for pool in $sorted_pools; do
        local a="${POOL_STATS_ACTIVE[$pool]}"
        local act="${POOL_STATS_ACTIVATING[$pool]}"
        local deact="${POOL_STATS_DEACTIVATING[$pool]}"

        printf "${LIGHTPURPLE}%-20s${NOCOLOR} ${WHITE}%-12s${NOCOLOR} ${GREEN}%-12s${NOCOLOR} ${RED}%-12s${NOCOLOR}\n" \
            "$pool" "$a" "$act" "$deact"
    done
}







### 🚀 EXECUTE ANALYSIS ###

load_stakepools_list
analyze_validator_stake_pools "$THIS_SOLANA_ADRESS" "$SOLANA_CLUSTER"

