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

start_time=$(date +%s)

# --- Cleanup logic for temporary files ---
TMP_FILES=()
cleanup() {
  rm -f "${TMP_FILES[@]}"
}
trap cleanup EXIT INT TERM
# ---

# colors
CYAN='\033[0;36m'
RED='\033[0;31m'
GREEN='\033[0;32m'
DARKGRAY='\033[1;30m'
LIGHTGRAY='\033[0;37m'
YELLOW='\033[1;33m'
LIGHTPURPLE='\033[1;35m'
LIGHTBLUE='\033[1;34m'
UNDERLINE='\033[4m'
NOCOLOR='\033[0m'

# Declare associative arrays for data aggregation
declare -A data
declare -A NAME_TO_KEY # for grouping and displaying original public keys

function display_help() {
  echo -e "${GREEN}Usage: $0 [OPTIONS] [SORT_CRITERIA...]${NOCOLOR}"
  echo ""
  echo "Checks stake pools statistics for a given Solana validator."
  echo ""
  echo "Options:"
  echo "  -h, --help                 Display this help message and exit."
  echo "  -i, --identity <PUBKEY>    Specify the validator identity public key to check (default: local solana address)."
  echo "  -u, --url <CLUSTER|RPC_URL> Specify Solana cluster (mainnet-beta, testnet, devnet) or a custom RPC URL."
  echo "                             Default: auto-detect from local solana config or mainnet-beta."
  echo "  --output <json>            Output data in valid JSON format (requires 'jq' and 'bc' to be installed)."
  echo ""
  echo "Aggregation (for text output only):"
  echo "  -p, --by-pool              Aggregate results by stake pool (default)."
  echo "  -g, --by-group             Aggregate results by predefined group."
  echo "  -c, --by-category          Aggregate results by predefined category."
  echo ""
  echo "Sorting Criteria (for text output only, can be repeated, applied in order):"
  echo "  1:KEY_AUTHORITY            Sort by key authority / pool name (string sort)."
  echo "  2:COUNT                    Sort by stake count (default: ASC). Add 'DESC' for descending (e.g., '2:DESC')."
  echo "  3:INFO                     Sort by info (string sort)."
  echo "  4:PERCENT                  Sort by percentage of total active stake (default: ASC)."
  echo "  5:ACTIVE                   Sort by active stake (default: ASC)."
  echo "  6:DEACTIVATING             Sort by deactivating stake (default: ASC)."
  echo "  7:ACTIVATING               Sort by activating stake (default: ASC)."
  echo ""
  echo "Examples:"
  echo "  $0"
  echo "  $0 -i 7d2m1D5h6... --output json | jq"
  echo "  $0 --by-pool 5:DESC 2:DESC"
  echo ""
  echo -e "${YELLOW}Stand with Ukraine 🇺🇦${NOCOLOR}"
  exit 0
}

# Defaults
DEFAULT_SOLANA_ADRESS=$(solana address 2>/dev/null)
SOLANA_IDENTITY="${DEFAULT_SOLANA_ADRESS}"
SOLANA_CLUSTER_ARG=""
AGGREGATION_MODE="pool"
SORTING_CRITERIAS=()
OUTPUT_MODE="text"

# Parse arguments
TEMP=$(getopt -o hi:u:pgc --long help,identity:,url:,by-pool,by-group,by-category,output: -n '$0' -- "$@")

if [ $? -ne 0 ]; then
  echo -e "${RED}Error: Invalid arguments.${NOCOLOR}" >&2
  display_help
fi

eval set -- "$TEMP"

while true; do
  case "$1" in
    -h | --help)
      display_help
      ;;
    -i | --identity)
      SOLANA_IDENTITY="$2"
      shift 2
      ;;
    -u | --url)
      SOLANA_CLUSTER_ARG="$2"
      shift 2
      ;;
    -p | --by-pool)
      AGGREGATION_MODE="pool"
      shift
      ;;
    -g | --by-group)
      AGGREGATION_MODE="group"
      shift
      ;;
    -c | --by-category)
      AGGREGATION_MODE="category"
      shift
      ;;
    --output)
      if [[ "$2" == "json" ]]; then
        if ! command -v jq &> /dev/null; then
            echo -e "${RED}Error: 'jq' is not installed. Please install jq to use JSON output.${NOCOLOR}" >&2
            exit 1
        fi
        if ! command -v bc &> /dev/null; then
            echo -e "${RED}Error: 'bc' is not installed. Please install bc to use JSON output.${NOCOLOR}" >&2
            exit 1
        fi
        OUTPUT_MODE="json"
      else
        echo -e "${RED}Error: Invalid value for --output. Only 'json' is supported.${NOCOLOR}" >&2
        exit 1
      fi
      shift 2
      ;;
    --)
      shift
      break
      ;;
    *)
      echo -e "${RED}Internal error!${NOCOLOR}" >&2
      exit 1
      ;;
  esac
done

SORTING_CRITERIAS=("$@")
if [[ "$OUTPUT_MODE" == "text" ]]; then
    [[ ${#SORTING_CRITERIAS[@]} -eq 0 ]] && SORTING_CRITERIAS=("5:DESC")
fi

SOLANA_CLUSTER_CLI_OPT=""
CLUSTER_NAME_RAW=""

if [[ -n "$SOLANA_CLUSTER_ARG" ]]; then
  case "$SOLANA_CLUSTER_ARG" in
    mainnet-beta)
      SOLANA_CLUSTER_CLI_OPT="-um"
      CLUSTER_NAME_RAW="mainnet-beta"
      CLUSTER_NAME="(Mainnet)"
      ;;
    testnet)
      SOLANA_CLUSTER_CLI_OPT="-ut"
      CLUSTER_NAME_RAW="testnet"
      CLUSTER_NAME="(TESTNET)"
      ;;
    devnet)
      SOLANA_CLUSTER_CLI_OPT="-ud"
      CLUSTER_NAME_RAW="devnet"
      CLUSTER_NAME="(Devnet)"
      ;;
    *)
      SOLANA_CLUSTER_CLI_OPT="--url $SOLANA_CLUSTER_ARG"
      CLUSTER_NAME_RAW="$SOLANA_CLUSTER_ARG"
      CLUSTER_NAME="(Custom RPC)"
      ;;
  esac
else
  THIS_CONFIG_RPC=$(solana config get 2>/dev/null | awk -F': ' '/RPC URL:/ {print $2}')
  if [[ "$THIS_CONFIG_RPC" == *testnet* ]]; then
    SOLANA_CLUSTER_CLI_OPT="-ut"
    CLUSTER_NAME_RAW="testnet"
    CLUSTER_NAME="(TESTNET - Local Config)"
  elif [[ "$THIS_CONFIG_RPC" == *mainnet* ]]; then
    SOLANA_CLUSTER_CLI_OPT="-um"
    CLUSTER_NAME_RAW="mainnet-beta"
    CLUSTER_NAME="(Mainnet - Local Config)"
  elif [[ "$THIS_CONFIG_RPC" == *devnet* ]]; then
    SOLANA_CLUSTER_CLI_OPT="-ud"
    CLUSTER_NAME_RAW="devnet"
    CLUSTER_NAME="(Devnet - Local Config)"
  else
    SOLANA_CLUSTER_CLI_OPT="-um"
    CLUSTER_NAME_RAW="mainnet-beta"
    CLUSTER_NAME="(Mainnet - Default)"
  fi
fi

# Function to safely parse CSV with proper handling of quoted fields
function parse_csv_to_json() {
    local csv_file="$1"
    # Use perl for reliable CSV parsing
    if command -v perl &>/dev/null; then
        perl -e '
            use strict;
            use warnings;
            
            open(my $fh, "<", $ARGV[0]) or die "Cannot open file: $!";
            my $header = <$fh>;  # Skip header
            
            print "[";
            my $first = 1;
            
            while (my $line = <$fh>) {
                chomp $line;
                next if $line =~ /^#/ || $line eq "";
                
                # Parse CSV line properly
                my @fields = ();
                my $field = "";
                my $in_quotes = 0;
                
                for (my $i = 0; $i < length($line); $i++) {
                    my $char = substr($line, $i, 1);
                    
                    if ($char eq "\"") {
                        if ($i + 1 < length($line) && substr($line, $i + 1, 1) eq "\"") {
                            $field .= "\"";
                            $i++;
                        } else {
                            $in_quotes = !$in_quotes;
                        }
                    } elsif ($char eq "," && !$in_quotes) {
                        push @fields, $field;
                        $field = "";
                    } else {
                        $field .= $char;
                    }
                }
                push @fields, $field;
                
                # Ensure 9 fields
                push @fields, ("") x (9 - @fields) if @fields < 9;
                
                # Skip if no public_key (index 4)
                next if !$fields[4];
                
                # Clean fields
                for (@fields) {
                    s/^\s+|\s+$//g;
                    s/\"/\\\"/g;
                }
                
                print "," if !$first;
                $first = 0;
                
                printf "{\"short_name\":\"%s\",\"type\":\"%s\",\"group\":\"%s\",\"category\":\"%s\",\"public_key\":\"%s\",\"long_name\":\"%s\",\"description\":\"%s\",\"url\":\"%s\",\"image\":\"%s\"}",
                    @fields[0..8];
            }
            close($fh);
            
            print "]";
        ' "$csv_file"
    else
        # Fallback to awk if perl is not available
        awk -F',' '
        NR==1 { next }  # Skip header
        /^#/ || NF==0 { next }  # Skip comments and empty lines
        {
            # Handle each field, preserving empty ones
            gsub(/^[[:space:]]+|[[:space:]]+$/, "")
            
            # Ensure we have 9 fields
            for (i = NF + 1; i <= 9; i++) $i = ""
            
            # Skip if no public_key (field 5)
            if ($5 == "") next
            
            # Clean quotes
            for (i = 1; i <= 9; i++) {
                gsub(/^"|"$/, "", $i)
                gsub(/""/, "\"", $i)
            }
            
            # Output JSON
            printf "{\"short_name\":\"%s\",\"type\":\"%s\",\"group\":\"%s\",\"category\":\"%s\",\"public_key\":\"%s\",\"long_name\":\"%s\",\"description\":\"%s\",\"url\":\"%s\",\"image\":\"%s\"}\n",
                   $1, $2, $3, $4, $5, $6, $7, $8, $9
        }' "$csv_file" | jq -s '.'
    fi
}

STAKEPOOL_URL="https://raw.githubusercontent.com/SOFZP/Solana-Stake-Pools-Research/main/stakepools_list.csv"
STAKEPOOL_CACHE="${HOME}/.cache/stakepools_list.csv"
STAKEPOOL_TMP="/tmp/stakepools_list_tmp.csv"
mkdir -p "$(dirname "$STAKEPOOL_CACHE")"
download_needed=true
if [[ -f "$STAKEPOOL_CACHE" ]]; then
  curl -sf "$STAKEPOOL_URL" -o "$STAKEPOOL_TMP" || {
    download_needed=false
  }
  if [[ "$download_needed" == true ]]; then
    old_hash=$(sha256sum "$STAKEPOOL_CACHE" 2>/dev/null | awk '{print $1}')
    new_hash=$(sha256sum "$STAKEPOOL_TMP" 2>/dev/null | awk '{print $1}')
    if [[ "$old_hash" != "$new_hash" ]]; then
      mv "$STAKEPOOL_TMP" "$STAKEPOOL_CACHE"
    fi
  fi
else
  curl -sf "$STAKEPOOL_URL" -o "$STAKEPOOL_CACHE" || {
    echo -e "${RED}❌ Failed to fetch stakepools_list.csv and no local copy exists.${NOCOLOR}"
    exit 1
  }
fi
rm -f "$STAKEPOOL_TMP"
STAKEPOOL_CONF="$STAKEPOOL_CACHE"

retry_command() {
    local command_str="$1"
    local max_attempts="${2:-5}"
    local default_value="${3:-"N/A"}"
    local show_errors="${4:-"yes"}"
    local attempt=1
    local output=""
    while (( attempt <= max_attempts )); do
        output=$(eval "$command_str" 2>/dev/null)
        if [[ -n "$output" ]]; then
            echo "$output"
            return 0
        else
            sleep 3
        fi
        ((attempt++))
    done
    [[ "$show_errors" =~ ^(yes|true)$ ]] && \
        echo -e "${RED}Failed to execute command after $max_attempts attempts.\nCommand: $command_str${NOCOLOR}" >&2
    echo "$default_value"; return 1
}

function sort_data() {
    local sortable_data=()
    local sorted_data
    local sort_args=()
    for key in "${!data[@]}"; do
        sortable_data+=("$key:${data[$key]}")
    done
    for criterion in "$@"; do
        IFS=':' read -r col_num order <<< "$criterion"
        local column_index
        local sort_type_flag=""
        local order_flag=""
        [[ "$order" == "DESC" ]] && order_flag="r"
        case "$col_num" in
            1) column_index=1; sort_type_flag="" ;;
            2) column_index=2; sort_type_flag="g" ;;
            3) column_index=3; sort_type_flag="" ;;
            4) column_index=4; sort_type_flag="g" ;;
            5) column_index=5; sort_type_flag="g" ;;
            6) column_index=6; sort_type_flag="g" ;;
            7) column_index=7; sort_type_flag="g" ;;
            *) continue ;;
        esac
        sort_args+=("-k${column_index},${column_index}${order_flag}${sort_type_flag}")
    done
    if [[ ${#sort_args[@]} -eq 0 ]]; then
        sort_args=("-k5,5rg")
    fi
    sorted_data=$(printf "%s\n" "${sortable_data[@]}" | LC_NUMERIC=C sort -t':' "${sort_args[@]}")
    while IFS=':' read -r key count info percent_val active_val deactivating_val activating_val; do
        [[ -z "$info" || "$info" == "\\t" ]] && info=""
        percent=$(printf "%.3f%%" "$percent_val")
        display_key="${NAME_TO_KEY[$key]:-$key}"
        if (( ${#display_key} > 45 )); then display_key="{${display_key:0:29}..............}"; fi
        active_sol=$(printf "%.3f" "$active_val")
        deactivating_sol=$(printf "%.3f" "$deactivating_val")
        activating_sol=$(printf "%.3f" "$activating_val")
        [[ $(echo "$active_sol == 0" | bc -l) -eq 1 ]] && active_sol="0"
        [[ $(echo "$deactivating_sol == 0" | bc -l) -eq 1 ]] && deactivating_sol="0"
        [[ $(echo "$activating_sol == 0" | bc -l) -eq 1 ]] && activating_sol="0"
        printf "%-47s %-7d ${LIGHTPURPLE}%-23s${NOCOLOR} ${LIGHTBLUE}%-15s${NOCOLOR} ${CYAN}%-15s${NOCOLOR} ${RED}%-15s${NOCOLOR} ${GREEN}%-15s${NOCOLOR}\n" \
          "$display_key" "$count" "$info" "$percent" "$active_sol" "$deactivating_sol" "$activating_sol"
    done <<< "$sorted_data"
}

if [[ -z "$SOLANA_IDENTITY" ]]; then
    echo -e "${RED}❌ Solana identity public key is not set. Please provide it with -i or --identity option, or ensure 'solana address' command works.${NOCOLOR}"
    exit 1
fi

VALIDATORS_JSON=$(retry_command "solana ${SOLANA_CLUSTER_CLI_OPT} validators --output json-compact" 5 "" false)
if [[ "$VALIDATORS_JSON" == "N/A" ]]; then
    echo -e "${RED}❌ Failed to fetch validator list. Please check your solana CLI configuration and network connection.${NOCOLOR}"
    exit 1
fi
THIS_VALIDATOR_JSON=$(echo "$VALIDATORS_JSON" | jq --arg ID "$SOLANA_IDENTITY" '.validators[] | select(.identityPubkey==$ID)')
YOUR_VOTE_ACCOUNT=$(echo "$THIS_VALIDATOR_JSON" | jq -r '.voteAccountPubkey' 2>/dev/null)
if [[ -z "$YOUR_VOTE_ACCOUNT" || "$YOUR_VOTE_ACCOUNT" == "null" ]]; then
  echo -e "${RED}❌ $SOLANA_IDENTITY — can't find vote account!${NOCOLOR}"
  exit 1
fi

VALIDATOR_NAMES_JSON=$(retry_command "solana ${SOLANA_CLUSTER_CLI_OPT} validator-info get --output json" 5 "null" false)
declare -A VALIDATOR_NAMES
if [[ "$VALIDATOR_NAMES_JSON" != "null" ]]; then
    while IFS=$'\t' read -r identity name; do
        [[ -z "$name" ]] && name="NO NAME"
        VALIDATOR_NAMES["$identity"]="$name"
    done < <(echo "$VALIDATOR_NAMES_JSON" | jq -r '.[] | "\(.identityPubkey)\t\(.info.name // "NO NAME")"')
fi
NODE_NAME_RAW="${VALIDATOR_NAMES[$SOLANA_IDENTITY]:-NO NAME}"
NODE_NAME_DISPLAY=$(echo "$NODE_NAME_RAW" | sed 's/ /\\u00A0/g')

EPOCH_INFO_JSON=$(retry_command "solana ${SOLANA_CLUSTER_CLI_OPT} epoch-info --output json" 5 "{}" false)
THIS_EPOCH=$(echo "$EPOCH_INFO_JSON" | jq -r '.epoch // "N/A"')
EPOCH_PERCENT_RAW=$(echo "$EPOCH_INFO_JSON" | jq -r '.epochCompletedPercent // "N/A"')
EPOCH_PERCENT=$(printf "%.0f" "$EPOCH_PERCENT_RAW")

NODE_WITHDRAW_AUTHORITY=$(retry_command "solana ${SOLANA_CLUSTER_CLI_OPT} vote-account ${YOUR_VOTE_ACCOUNT} | grep 'Withdraw' | awk '{print \$NF}'" 5 "" false)

declare -A STAKE_AUTHORITY_MAP
declare -A STAKE_WITHDRAWER_MAP
declare -A POOL_DEFINITIONS
declare -a POOL_DEF_ORDER

# Parse CSV once and store in variable
PARSED_CSV_JSON=$(parse_csv_to_json "$STAKEPOOL_CONF")

# Process parsed data - УВАГА: порядок полів відповідає CSV!
while IFS=$'\t' read -r short_name type group category public_key long_name description url image; do
  [[ -z "$public_key" ]] && continue
  POOL_DEF_ORDER+=("$short_name")
  # Зберігаємо в оригінальному порядку для сумісності
  POOL_DEFINITIONS["$short_name"]="$short_name\t$type\t$group\t$category\t$public_key\t$long_name\t$image\t$description\t$url"
  resolved_pubkey="${public_key//YOUR_NODE_WITHDRAW_AUTHORITY/$NODE_WITHDRAW_AUTHORITY}"
  resolved_pubkey="${resolved_pubkey//YOUR_NODE_IDENTITY/$SOLANA_IDENTITY}"
  local_info_string="${short_name}:${group}:${category}"
  if [[ "$type" == "S" ]]; then
    STAKE_AUTHORITY_MAP["$resolved_pubkey"]="$local_info_string"
  elif [[ "$type" == "W" ]]; then
    STAKE_WITHDRAWER_MAP["$resolved_pubkey"]="$local_info_string"
  fi
done < <(echo "$PARSED_CSV_JSON" | jq -r '.[] | [.short_name, .type, .group, .category, .public_key, .long_name, .description, .url, .image] | @tsv')

ALL_MY_STAKES_JSON=$(retry_command "solana ${SOLANA_CLUSTER_CLI_OPT} stakes ${YOUR_VOTE_ACCOUNT} --output json-compact" 10 "" false)

TOTAL_ACTIVE_STAKE_LAMPORTS=0
TOTAL_ACTIVATING_STAKE_LAMPORTS=0
TOTAL_DEACTIVATING_STAKE_LAMPORTS=0
TOTAL_STAKE_COUNT_OVERALL=0

if [[ "$OUTPUT_MODE" == "json" ]]; then
    declare -A data_by_pool data_by_group data_by_category
    declare -A keys_by_pool keys_by_group keys_by_category
    declare -A other_stake_pubkeys

    while IFS=$'\t' read -r stake_pubkey staker withdrawer active_lamports activating_lamports deactivating_lamports; do
        ((TOTAL_STAKE_COUNT_OVERALL++))
        is_matched=false
        pool_name=""; group_name=""; category_name=""; authority_key=""
        if [[ -n "${STAKE_AUTHORITY_MAP[$staker]}" ]]; then
            IFS=':' read -r p g c <<< "${STAKE_AUTHORITY_MAP[$staker]}"; pool_name=$p; group_name=$g; category_name=$c;
            authority_key="$staker"; is_matched=true
        elif [[ -n "${STAKE_WITHDRAWER_MAP[$withdrawer]}" ]]; then
            IFS=':' read -r p g c <<< "${STAKE_WITHDRAWER_MAP[$withdrawer]}"; pool_name=$p; group_name=$g; category_name=$c;
            authority_key="$withdrawer"; is_matched=true
        fi
        if [[ "$is_matched" == true ]]; then
            current_data=${data_by_pool[$pool_name]:-"0:0:0:0"}; IFS=':' read -r c a d act <<< "$current_data"
            data_by_pool[$pool_name]="$((c+1)):$((a+active_lamports)):$((d+deactivating_lamports)):$((act+activating_lamports))"
            if [[ ! "${keys_by_pool[$pool_name]}" =~ (^|[+])${authority_key}($|[+]) ]]; then keys_by_pool[$pool_name]="${keys_by_pool[$pool_name]:+${keys_by_pool[$pool_name]}+}$authority_key"; fi
            current_data=${data_by_group[$group_name]:-"0:0:0:0"}; IFS=':' read -r c a d act <<< "$current_data"
            data_by_group[$group_name]="$((c+1)):$((a+active_lamports)):$((d+deactivating_lamports)):$((act+activating_lamports))"
            if [[ ! "${keys_by_group[$group_name]}" =~ (^|[+])${authority_key}($|[+]) ]]; then keys_by_group[$group_name]="${keys_by_group[$group_name]:+${keys_by_group[$group_name]}+}$authority_key"; fi
            current_data=${data_by_category[$category_name]:-"0:0:0:0"}; IFS=':' read -r c a d act <<< "$current_data"
            data_by_category[$category_name]="$((c+1)):$((a+active_lamports)):$((d+deactivating_lamports)):$((act+activating_lamports))"
            if [[ ! "${keys_by_category[$category_name]}" =~ (^|[+])${authority_key}($|[+]) ]]; then keys_by_category[$category_name]="${keys_by_category[$category_name]:+${keys_by_category[$category_name]}+}$authority_key"; fi
        else
            other_stake_pubkeys["$stake_pubkey"]="$active_lamports:$activating_lamports:$deactivating_lamports"
        fi
        TOTAL_ACTIVE_STAKE_LAMPORTS=$((TOTAL_ACTIVE_STAKE_LAMPORTS + active_lamports))
        TOTAL_ACTIVATING_STAKE_LAMPORTS=$((TOTAL_ACTIVATING_STAKE_LAMPORTS + activating_lamports))
        TOTAL_DEACTIVATING_STAKE_LAMPORTS=$((TOTAL_DEACTIVATING_STAKE_LAMPORTS + deactivating_lamports))
    done < <(echo "$ALL_MY_STAKES_JSON" | jq -r '.[] | [.stakePubkey, .staker, .withdrawer, (.activeStake // 0), (.activatingStake // 0), (.deactivatingStake // 0)] | @tsv')
    if (( ${#other_stake_pubkeys[@]} > 0 )); then
        other_active=0; other_activating=0; other_deactivating=0; other_count=0; other_pubkeys_list=""
        for pubkey in "${!other_stake_pubkeys[@]}"; do
            IFS=':' read -r a act deact <<< "${other_stake_pubkeys[$pubkey]}"
            other_active=$((other_active + a)); other_activating=$((other_activating + act)); other_deactivating=$((other_deactivating + deact)); ((other_count++))
            other_pubkeys_list="${other_pubkeys_list:+$other_pubkeys_list+}$pubkey"
        done
        other_data_string="$other_count:$other_active:$other_deactivating:$other_activating"
        data_by_pool["OTHER"]=$other_data_string; data_by_group["OTHER"]=$other_data_string; data_by_category["OTHER"]=$other_data_string
        keys_by_pool["OTHER"]=""; keys_by_group["OTHER"]=""; keys_by_category["OTHER"]=""
    fi
    current_time=$(date +%s); elapsed=$((current_time - start_time))

    pool_defs_json_stream=""
    conf_keys=("short_name" "type" "group" "category" "public_key" "long_name" "image" "description" "url")
    for name in "${POOL_DEF_ORDER[@]}"; do
        def_string="${POOL_DEFINITIONS[$name]}"
        jq_args=()
        counter=0
        while IFS= read -r value; do
            key="${conf_keys[$counter]}"; [[ "$value" == "<fill>" ]] && value=""
            jq_args+=(--arg "$key" "$value"); ((counter++))
        done < <(echo -e "$def_string" | tr '\t' '\n')
        pool_defs_json_stream+=$(jq -n "${jq_args[@]}" '{$short_name, $type, $group, $category, $public_key, $long_name, $image, $description, $url}')
    done
    
    gen_agg_json() {
        local -n data_map=$1; local -n keys_map=$2
        agg_json_stream=""
        for name in "${!data_map[@]}"; do
            IFS=':' read -r count active deactivating activating <<< "${data_map[$name]}"
            if [[ "$TOTAL_ACTIVE_STAKE_LAMPORTS" -gt 0 ]]; then
                percent_str=$(LC_NUMERIC=C printf "%.12f" $(echo "scale=15; $active / $TOTAL_ACTIVE_STAKE_LAMPORTS" | bc))
            else
                percent_str="0.000000000000"
            fi
            
            if [[ "$name" == "OTHER" ]]; then
                authority_keys_json='["other_stake_account_keys"]'
            else
                authority_keys_json=$(echo -n "${keys_map[$name]}" | jq -R 'split("+") | map(select(length > 0))')
            fi

            if [[ -z "$authority_keys_json" ]]; then
                authority_keys_json="[]"
            fi
            line=$(jq -n --arg name "$name" --argjson count "$count" --arg percent "$percent_str" --argjson active_lamports "$active" --argjson deactivating_lamports "$deactivating" --argjson activating_lamports "$activating" --argjson authority_keys "$authority_keys_json" \
                '{name: $name, count: $count, percent: $percent, active_lamports: $active_lamports, deactivating_lamports: $deactivating_lamports, activating_lamports: $activating_lamports, authority_keys: $authority_keys}')
            
            agg_json_stream+=$line
        done
        echo "$agg_json_stream"
    }
    
    tmp_pool_defs=$(mktemp); TMP_FILES+=("$tmp_pool_defs")
    tmp_agg_pool=$(mktemp);  TMP_FILES+=("$tmp_agg_pool")
    tmp_agg_group=$(mktemp); TMP_FILES+=("$tmp_agg_group")
    tmp_agg_category=$(mktemp); TMP_FILES+=("$tmp_agg_category")
    tmp_other_keys=$(mktemp); TMP_FILES+=("$tmp_other_keys")

    echo "$pool_defs_json_stream" | jq -s . > "$tmp_pool_defs"
    gen_agg_json data_by_pool keys_by_pool | jq -s . > "$tmp_agg_pool"
    gen_agg_json data_by_group keys_by_group | jq -s . > "$tmp_agg_group"
    gen_agg_json data_by_category keys_by_category | jq -s . > "$tmp_agg_category"
    echo "$other_pubkeys_list" | jq -R 'split("+") | map(select(length > 0))' > "$tmp_other_keys"

    jq -n \
        --arg timestamp_utc "$(date -u --iso-8601=seconds)" --argjson epoch "$THIS_EPOCH" --argjson epoch_completed_percent "$EPOCH_PERCENT" --arg cluster_name "$CLUSTER_NAME_RAW" \
        --slurpfile pool_defs "$tmp_pool_defs" \
        --arg identity_pubkey "$SOLANA_IDENTITY" --arg vote_pubkey "$YOUR_VOTE_ACCOUNT" --arg validator_name "$NODE_NAME_RAW" --argjson data_fetch_time_seconds "$elapsed" \
        --argjson total_stake_accounts "$TOTAL_STAKE_COUNT_OVERALL" --argjson total_active_lamports "$TOTAL_ACTIVE_STAKE_LAMPORTS" --argjson total_deactivating_lamports "$TOTAL_DEACTIVATING_STAKE_LAMPORTS" --argjson total_activating_lamports "$TOTAL_ACTIVATING_STAKE_LAMPORTS" \
        --slurpfile agg_pool "$tmp_agg_pool" \
        --slurpfile agg_group "$tmp_agg_group" \
        --slurpfile agg_category "$tmp_agg_category" \
        --slurpfile other_keys "$tmp_other_keys" \
        '{ 
            metadata: { timestamp_utc: $timestamp_utc, epoch: $epoch, epoch_completed_percent: $epoch_completed_percent, cluster_name: $cluster_name }, 
            pool_definitions: $pool_defs[0], 
            validators: [ { 
                info: { identity_pubkey: $identity_pubkey, vote_pubkey: $vote_pubkey, name: $validator_name }, 
                totals: { total_stake_accounts: $total_stake_accounts, total_active_lamports: $total_active_lamports, total_deactivating_lamports: $total_deactivating_lamports, total_activating_lamports: $total_activating_lamports },
                aggregations: { by_pool: $agg_pool[0], by_group: $agg_group[0], by_category: $agg_category[0] },
                other_stake_account_keys: $other_keys[0]
            } ], 
            script_info: { execution_time_seconds: $data_fetch_time_seconds } 
        }'
else
    echo -e "${DARKGRAY}All Stakers of $NODE_NAME_DISPLAY | $YOUR_VOTE_ACCOUNT | Epoch ${THIS_EPOCH} ${CLUSTER_NAME} | Aggregation: ${AGGREGATION_MODE^^}${NOCOLOR}"
    declare -A STAKES_FOR_OTHER
    while IFS=$'\t' read -r stake_pubkey staker withdrawer active_lamports activating_lamports deactivating_lamports; do
        local_name=""; info_name=""; is_matched=false; authority_key=""
        pool_name=""; group_name=""; category_name=""
        ((TOTAL_STAKE_COUNT_OVERALL++))

        if [[ -n "${STAKE_AUTHORITY_MAP[$staker]}" ]]; then
            IFS=':' read -r pool_name group_name category_name <<< "${STAKE_AUTHORITY_MAP[$staker]}"; authority_key="$staker"; is_matched=true
        elif [[ -n "${STAKE_WITHDRAWER_MAP[$withdrawer]}" ]]; then
            IFS=':' read -r pool_name group_name category_name <<< "${STAKE_WITHDRAWER_MAP[$withdrawer]}"; authority_key="$withdrawer"; is_matched=true
        fi

        if [[ "$is_matched" == true ]]; then
            case "$AGGREGATION_MODE" in
                pool) local_name="${pool_name}"; info_name="${pool_name}" ;;
                group) local_name="${group_name}"; info_name="${group_name}" ;;
                category) local_name="${category_name}"; info_name="${category_name}" ;;
            esac
            
            if [[ -z "${data[$local_name]}" ]]; then
                data["$local_name"]="0:${info_name}:0.000:0.000:0.000:0.000"
            fi

            if [[ -z "${NAME_TO_KEY[$local_name]}" ]]; then
              NAME_TO_KEY[$local_name]="$authority_key"
            elif [[ ! "${NAME_TO_KEY[$local_name]}" =~ (^|[+])${authority_key}($|[+]) ]]; then
              NAME_TO_KEY[$local_name]="${NAME_TO_KEY[$local_name]}+$authority_key"
            fi
            
            IFS=":" read -r current_count current_info _ current_active_sol current_deactivating_sol current_activating_sol <<< "${data[$local_name]}"
            new_count=$((current_count + 1))
            new_active_sol=$(awk -v ca="$current_active_sol" -v al="$active_lamports" 'BEGIN{printf "%.3f", ca + al/1e9}')
            new_deactivating_sol=$(awk -v cd="$current_deactivating_sol" -v dl="$deactivating_lamports" 'BEGIN{printf "%.3f", cd + dl/1e9}')
            new_activating_sol=$(awk -v cact="$current_activating_sol" -v actl="$activating_lamports" 'BEGIN{printf "%.3f", cact + actl/1e9}')
            data["$local_name"]="$new_count:${current_info}:0.000:$new_active_sol:$new_deactivating_sol:$new_activating_sol"
        else
            STAKES_FOR_OTHER["$stake_pubkey"]="${active_lamports}:${activating_lamports}:${deactivating_lamports}"
        fi
        TOTAL_ACTIVE_STAKE_LAMPORTS=$((TOTAL_ACTIVE_STAKE_LAMPORTS + active_lamports))
        TOTAL_ACTIVATING_STAKE_LAMPORTS=$((TOTAL_ACTIVATING_STAKE_LAMPORTS + activating_lamports))
        TOTAL_DEACTIVATING_STAKE_LAMPORTS=$((TOTAL_DEACTIVATING_STAKE_LAMPORTS + deactivating_lamports))
    done < <(echo "$ALL_MY_STAKES_JSON" | jq -r '.[] | [.stakePubkey, .staker, .withdrawer, (.activeStake // 0), (.activatingStake // 0), (.deactivatingStake // 0)] | @tsv')
    if (( ${#STAKES_FOR_OTHER[@]} > 0 )); then
        other_active_sum_lamports=0; other_deactivating_sum_lamports=0; other_activating_sum_lamports=0; other_count=0
        for stake_pubkey in "${!STAKES_FOR_OTHER[@]}"; do
            IFS=':' read -r active_l activating_l deactivating_l <<< "${STAKES_FOR_OTHER[$stake_pubkey]}"
            other_active_sum_lamports=$((other_active_sum_lamports + active_l)); other_deactivating_sum_lamports=$((other_deactivating_sum_lamports + deactivating_l)); other_activating_sum_lamports=$((other_activating_sum_lamports + activating_l)); ((other_count++))
        done
        other_active_sol=$(awk -v n="$other_active_sum_lamports" 'BEGIN{printf "%.3f", n/1e9}'); other_deactivating_sol=$(awk -v n="$other_deactivating_sum_lamports" 'BEGIN{printf "%.3f", n/1e9}'); other_activating_sol=$(awk -v n="$other_activating_sum_lamports" 'BEGIN{printf "%.3f", n/1e9}')
        data["OTHER"]="$other_count:OTHER:0.000:$other_active_sol:$other_deactivating_sol:$other_activating_sol"; NAME_TO_KEY["OTHER"]="OTHER"
    fi
    for key in "${!data[@]}"; do
        IFS=":" read -r current_count current_info _ current_active_sol current_deactivating_sol current_activating_sol <<< "${data[$key]}"
        current_active_lamports_for_percent=$(awk -v n="$current_active_sol" 'BEGIN{printf "%.0f", n*1e9}')
        if (( $(echo "$TOTAL_ACTIVE_STAKE_LAMPORTS == 0" | bc -l) )); then calculated_percent="0.000"; else calculated_percent=$(awk -v a="$current_active_lamports_for_percent" -v b="$TOTAL_ACTIVE_STAKE_LAMPORTS" 'BEGIN{printf "%.3f", 100 * a / b}'); fi
        data["$key"]="$current_count:$current_info:$calculated_percent:$current_active_sol:$current_deactivating_sol:$current_activating_sol"
    done
    echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"
    echo -e "${UNDERLINE}Key Authority\t\t\t\t\tCount\t${LIGHTPURPLE}${UNDERLINE}Info\t\t\t${LIGHTBLUE}${UNDERLINE}Percent\t\t${CYAN}${UNDERLINE}Active Stake\t${RED}${UNDERLINE}Deactivating\t${GREEN}${UNDERLINE}Activating${NOCOLOR}"
    sort_data "${SORTING_CRITERIAS[@]}"
    echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"
    TOTAL_ACTIVE_STAKE_DISPLAY=$(awk -v n="$TOTAL_ACTIVE_STAKE_LAMPORTS" 'BEGIN{printf "%.3f", n/1e9}'); ACTIVATING_STAKE_DISPLAY=$(awk -v n="$TOTAL_ACTIVATING_STAKE_LAMPORTS" 'BEGIN{printf "%.3f", n/1e9}'); DEACTIVATING_STAKE_DISPLAY=$(awk -v n="$TOTAL_DEACTIVATING_STAKE_LAMPORTS" 'BEGIN{printf "%.3f", n/1e9}')
    [[ $(echo "$TOTAL_ACTIVE_STAKE_DISPLAY == 0" | bc -l) -eq 1 ]] && TOTAL_ACTIVE_STAKE_DISPLAY="0"; [[ $(echo "$ACTIVATING_STAKE_DISPLAY == 0" | bc -l) -eq 1 ]] && ACTIVATING_STAKE_DISPLAY="0"; [[ $(echo "$DEACTIVATING_STAKE_DISPLAY == 0" | bc -l) -eq 1 ]] && DEACTIVATING_STAKE_DISPLAY="0"
    printf "%-47s %-7d %-23s ${LIGHTBLUE}%-15s${NOCOLOR} ${CYAN}%-15s${NOCOLOR} ${RED}%-15s${NOCOLOR} ${GREEN}%-15s${NOCOLOR}\n" \
      "TOTAL:" "$TOTAL_STAKE_COUNT_OVERALL" "" "100.000%" "$TOTAL_ACTIVE_STAKE_DISPLAY" "$DEACTIVATING_STAKE_DISPLAY" "$ACTIVATING_STAKE_DISPLAY"
    current_time=$(date +%s); elapsed=$((current_time - start_time)); elapsed_fmt=$(printf '%02d:%02d' $((elapsed/60)) $((elapsed%60)))
    echo -e "${LIGHTGRAY}----------${elapsed_fmt} elapsed----------${NOCOLOR}"; echo -e "${NOCOLOR}"
fi