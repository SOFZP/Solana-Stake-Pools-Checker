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

declare -A data
declare -A CHECKED_KEYS

# stakepools_list.conf from GitHub
STAKEPOOL_URL="https://raw.githubusercontent.com/SOFZP/Solana-Stake-Pools-Research/main/stakepools_list.conf"
STAKEPOOL_CACHE="${HOME}/.cache/stakepools_list.conf"
STAKEPOOL_TMP="/tmp/stakepools_list_tmp.conf"
mkdir -p "$(dirname "$STAKEPOOL_CACHE")"

download_needed=true

if [[ -f "$STAKEPOOL_CACHE" ]]; then
  curl -sf "$STAKEPOOL_URL" -o "$STAKEPOOL_TMP" || {
    echo -e "${YELLOW}⚠️  Cannot fetch latest stakepools_list.conf. Using local cache.${NOCOLOR}"
    download_needed=false
  }

  if [[ "$download_needed" == true ]]; then
    old_hash=$(sha256sum "$STAKEPOOL_CACHE" | awk '{print $1}')
    new_hash=$(sha256sum "$STAKEPOOL_TMP" | awk '{print $1}')
    
    if [[ "$old_hash" == "$new_hash" ]]; then
      # echo -e "${DARKGRAY}ℹ️  stakepools_list.conf is already up-to-date.${NOCOLOR}"
      rm -f "$STAKEPOOL_TMP"
      download_needed=false
    else
      mv "$STAKEPOOL_TMP" "$STAKEPOOL_CACHE"
      # echo -e "${GREEN}✅ stakepools_list.conf updated from GitHub${NOCOLOR}"
    fi
  fi
else
  curl -sf "$STAKEPOOL_URL" -o "$STAKEPOOL_CACHE" || {
    echo -e "${RED}❌ Failed to fetch stakepools_list.conf and no local copy exists.${NOCOLOR}"
    exit 1
  }
  echo -e "${GREEN}✅ stakepools_list.conf downloaded from GitHub${NOCOLOR}"
fi

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
        IFS=':' read -r column order <<< "$criterion"
        [[ "$order" == "DESC" ]] && order_flag="r" || order_flag=""
        sort_args+=("-k${column},${column}${order_flag}n")
    done

    sorted_data=$(printf "%s\n" "${sortable_data[@]}" | sort -t':' "${sort_args[@]}")

    while IFS=':' read -r key count info percent active deactivating activating; do
        # Порожнє info замінити на "-" або пробіл
        [[ -z "$info" || "$info" == "\\t" ]] && info=""
        percent=$(printf "%.3f%%" "$percent")
        
		display_key="${NAME_TO_KEY[$key]:-$key}"
		if (( ${#display_key} > 45 )); then display_key="{${display_key:0:29}..............}"; fi
		# display_key="$key"
        
        # Уникнення експоненційної нотації та обрізка .000
		[[ "$active" =~ ^0(\.0+)?$ ]] && active="0" || active=$(printf "%.3f" "$active")
		[[ "$deactivating" =~ ^0(\.0+)?$ ]] && deactivating="0" || deactivating=$(printf "%.3f" "$deactivating")
		[[ "$activating" =~ ^0(\.0+)?$ ]] && activating="0" || activating=$(printf "%.3f" "$activating")

        printf "%-47s %-7d ${LIGHTPURPLE}%-23s${NOCOLOR} ${LIGHTBLUE}%-15s${NOCOLOR} ${CYAN}%-15s${NOCOLOR} ${RED}%-15s${NOCOLOR} ${GREEN}%-15s${NOCOLOR}\n" \
          "$display_key" "$count" "$info" "$percent" "$active" "$deactivating" "$activating"
    done <<< "$sorted_data"
}





# Defaults
DEFAULT_CLUSTER='-ul'
DEFAULT_SOLANA_ADRESS=$(solana address)
THIS_CONFIG_RPC=$(solana config get | awk -F': ' '/RPC URL:/ {print $2}')

THIS_SOLANA_ADRESS=${1:-$DEFAULT_SOLANA_ADRESS}
SOLANA_CLUSTER=${2:-$DEFAULT_CLUSTER}
shift 2
AGGREGATION_MODE="pool"  # default

FILTERED_ARGS=()

for arg in "$@"; do
  case "$arg" in
    --by-pool)
      AGGREGATION_MODE="pool"
      ;;
    --by-group)
      AGGREGATION_MODE="group"
      ;;
    --by-category)
      AGGREGATION_MODE="category"
      ;;
    *)
      FILTERED_ARGS+=("$arg")
      ;;
  esac
done

SORTING_CRITERIAS=("${FILTERED_ARGS[@]}")



# Автовибір кластера, якщо -ul
if [[ "$SOLANA_CLUSTER" == "-ul" ]]; then
  case "$THIS_CONFIG_RPC" in
    *testnet*) SOLANA_CLUSTER="-ut" ;;
    *mainnet*) SOLANA_CLUSTER="-um" ;;
  esac
fi

# Ім’я кластера для виводу
case "$SOLANA_CLUSTER" in
  -ut) CLUSTER_NAME="(TESTNET)" ;;
  -um) CLUSTER_NAME="(Mainnet)" ;;
  -ul) CLUSTER_NAME="(Taken from Local)" ;;
  *)   CLUSTER_NAME="" ;;
esac

# Отримання voteAccount
YOUR_VOTE_ACCOUNT=""
for ((i=1; i<=5; i++)); do
  THIS_VALIDATOR_JSON=$(retry_command "solana ${SOLANA_CLUSTER} validators --output json-compact" 5 "" false | jq --arg ID "$THIS_SOLANA_ADRESS" '.validators[] | select(.identityPubkey==$ID)')
  YOUR_VOTE_ACCOUNT=$(echo "$THIS_VALIDATOR_JSON" | jq -r '.voteAccountPubkey' 2>/dev/null)
  [[ -n "$YOUR_VOTE_ACCOUNT" && "$YOUR_VOTE_ACCOUNT" != "null" ]] && break
  sleep 3
done

if [[ -z "$YOUR_VOTE_ACCOUNT" || "$YOUR_VOTE_ACCOUNT" == "null" ]]; then
  echo -e "${RED}❌ $THIS_SOLANA_ADRESS — can't find vote account!${NOCOLOR}"
  echo -e "${YELLOW}Possible reasons: --no-voting key active, RPC error, or validator wasn't vote ever or does not exist.${NOCOLOR}"
  exit 1
fi

# Отримуємо список всіх імен валідаторів одним запитом
VALIDATOR_NAMES_JSON=$(retry_command "solana ${SOLANA_CLUSTER} validator-info get --output json" 5 "null" false)
declare -A VALIDATOR_NAMES
while IFS=$'\t' read -r identity name; do
    if [[ -z "$name" ]]; then
        name="NO NAME"
    fi
    name=$(echo "$name" | sed 's/ /\\u00A0/g')
    VALIDATOR_NAMES["$identity"]="$name"
done < <(echo "$VALIDATOR_NAMES_JSON" | jq -r '.[] | "\(.identityPubkey)\t\(.info.name // "NO NAME")"')


NODE_NAME="${VALIDATOR_NAMES[$THIS_SOLANA_ADRESS]:-NO\\u00A0NAME}"


EPOCH_INFO=$(retry_command "solana ${SOLANA_CLUSTER} epoch-info 2> /dev/null" 5 "" false)
THIS_EPOCH=`echo -e "${EPOCH_INFO}" | grep 'Epoch: ' | sed 's/Epoch: //g' | awk '{print $1}'`

NODE_WITHDRAW_AUTHORITY=$(retry_command "solana ${SOLANA_CLUSTER} vote-account ${YOUR_VOTE_ACCOUNT} | grep 'Withdraw' | awk '{print \$NF}'" 5 "" false)

# Load data
STAKE_AUTHORITY=()
STAKE_AUTH_NAMES=()
POOL_AUTH_GROUPS=()
POOL_AUTH_CATEGORIES=()
STAKE_WTHDR=()
STAKE_NAMES=()
POOL_GROUPS=()
POOL_CATEGORIES=()

while IFS=$'\t' read -r short_name type group category public_key long_name image description url; do
  [[ "$short_name" =~ ^#.*$ || -z "$public_key" ]] && continue

  resolved_pubkey="${public_key//YOUR_NODE_WITHDRAW_AUTHORITY/$NODE_WITHDRAW_AUTHORITY}"
  resolved_pubkey="${resolved_pubkey//YOUR_NODE_IDENTITY/$THIS_SOLANA_ADRESS}"

  if [[ "$type" == "S" ]]; then
    STAKE_AUTHORITY+=("$resolved_pubkey")
    STAKE_AUTH_NAMES+=("$short_name")
    POOL_AUTH_GROUPS+=("$group")
    POOL_AUTH_CATEGORIES+=("$category")
  elif [[ "$type" == "W" ]]; then
    STAKE_WTHDR+=("$resolved_pubkey")
    STAKE_NAMES+=("$short_name")
    POOL_GROUPS+=("$group")
    POOL_CATEGORIES+=("$category")
  fi
done < "$STAKEPOOL_CONF"


# 🔁 Fast reverse-indexes for quick lookup
declare -A INDEX_BY_STAKE_AUTH
declare -A INDEX_BY_WTHDR

# Build lookup tables
for i in "${!STAKE_AUTHORITY[@]}"; do
    INDEX_BY_STAKE_AUTH["${STAKE_AUTHORITY[$i]}"]="$i"
done

for i in "${!STAKE_WTHDR[@]}"; do
    INDEX_BY_WTHDR["${STAKE_WTHDR[$i]}"]="$i"
done



echo -e "${DARKGRAY}All Stakers of $NODE_NAME | $YOUR_VOTE_ACCOUNT | Epoch ${THIS_EPOCH} ${CLUSTER_NAME} | Aggregation: ${AGGREGATION_MODE^^}${NOCOLOR}"


ALL_MY_STAKES_JSON=$(retry_command "solana ${SOLANA_CLUSTER} stakes ${YOUR_VOTE_ACCOUNT} --output json-compact" 10 "" false)

# 🔁 Фаза 1: кеш всіх stake акаунтів
declare -A STAKE_ACCOUNT_ACTIVE
declare -A STAKE_ACCOUNT_ACTIVATING
declare -A STAKE_ACCOUNT_DEACTIVATING
declare -A STAKE_ACCOUNT_STAKER
declare -A STAKE_ACCOUNT_WITHDRAWER

ALL_STAKE_PUBKEYS=()

while IFS=$'\t' read -r stake_key staker withdrawer active activating deactivating; do
  STAKE_ACCOUNT_ACTIVE["$stake_key"]="$active"
  STAKE_ACCOUNT_ACTIVATING["$stake_key"]="$activating"
  STAKE_ACCOUNT_DEACTIVATING["$stake_key"]="$deactivating"
  STAKE_ACCOUNT_STAKER["$stake_key"]="$staker"
  STAKE_ACCOUNT_WITHDRAWER["$stake_key"]="$withdrawer"
  ALL_STAKE_PUBKEYS+=("$stake_key")
done < <(jq -r '.[] | [.stakePubkey, .staker, .withdrawer, (.activeStake // 0), (.activatingStake // 0), (.deactivatingStake // 0)] | @tsv' <<< "$ALL_MY_STAKES_JSON")



ALL_MY_STAKES_FILE=$(mktemp "/tmp/stakes_json_$(date +%s%N)_XXXXXX.json")
echo "$ALL_MY_STAKES_JSON" > "$ALL_MY_STAKES_FILE"

cleanup_tmp_file() {
  [[ -f "$ALL_MY_STAKES_FILE" ]] && rm -f "$ALL_MY_STAKES_FILE"
  [[ -n "$UNUSED_KEYS_FILE" && -f "$UNUSED_KEYS_FILE" ]] && rm -f "$UNUSED_KEYS_FILE"
}
trap cleanup_tmp_file EXIT




TOTAL_ACTIVE_STAKE=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[].activeStake // 0] | add / 1e9' | awk '{printf "%.3f\n", $1}')
TOTAL_STAKE_COUNT=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[] | select(.activeStake // 0 > 0)] | length')

ACTIVATING_STAKE=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[].activatingStake // 0] | add / 1e9' | awk '{printf "%.3f\n", $1}')
ACTIVATING_STAKE_COUNT=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[] | select(.activatingStake // 0 > 0)] | length')

DEACTIVATING_STAKE=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[].deactivatingStake // 0] | add / 1e9' | awk '{printf "%.3f\n", $1}')
DEACTIVATING_STAKE_COUNT=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[] | select(.deactivatingStake // 0 > 0)] | length')

TOTAL_ACTIVE_STAKE_COUNT=$((TOTAL_STAKE_COUNT - ACTIVATING_STAKE_COUNT))


# processed=0
# start_time=$(date +%s)


# ➕ Фаза 1: STAKER KEY обробка
declare -A USED_STAKE_KEYS
declare -A NAME_TO_KEY  # для групування

for s_key in "${!INDEX_BY_STAKE_AUTH[@]}"; do
  index="${INDEX_BY_STAKE_AUTH[$s_key]}"

  case "$AGGREGATION_MODE" in
    pool) NAME="${STAKE_AUTH_NAMES[$index]}" ;;
    group) NAME="${POOL_AUTH_GROUPS[$index]:-UNKNOWN}" ;;
    category) NAME="${POOL_AUTH_CATEGORIES[$index]:-UNKNOWN}" ;;
  esac

  [[ -z "$NAME" ]] && continue

  for stake_pubkey in "${ALL_STAKE_PUBKEYS[@]}"; do
    
# ((processed++))
# if (( processed % 2000 == 0 )); then
#   current_time=$(date +%s)
#   elapsed=$((current_time - start_time))
#   total=$((${#ALL_STAKE_PUBKEYS[@]}*${#INDEX_BY_STAKE_AUTH[@]}))
# 
#   # Форматований час, що минув
#   elapsed_fmt=$(printf '%02d:%02d' $((elapsed/60)) $((elapsed%60)))
# 
#   # Оцінка часу до кінця (на основі середньої швидкості)
#   if (( processed > 0 )); then
# 	estimated_total_time=$(( (elapsed * total) / processed ))
# 	remaining=$((estimated_total_time - elapsed))
# 	remaining_fmt=$(printf '%02d:%02d' $((remaining/60)) $((remaining%60)))
#   else
# 	remaining_fmt="??:??"
#   fi
# 
#   echo -e "${LIGHTGRAY}STAKER KEY | Processed $processed / $total pairs... (${elapsed_fmt} elapsed, ~${remaining_fmt} remaining)${NOCOLOR}"
# fi

    [[ -n "${USED_STAKE_KEYS[$stake_pubkey]}" ]] && continue
    [[ "${STAKE_ACCOUNT_STAKER[$stake_pubkey]}" != "$s_key" ]] && continue

    active=${STAKE_ACCOUNT_ACTIVE[$stake_pubkey]}
    activating=${STAKE_ACCOUNT_ACTIVATING[$stake_pubkey]}
    deactivating=${STAKE_ACCOUNT_DEACTIVATING[$stake_pubkey]}

    active_gb=$(awk -v n="$active" 'BEGIN{printf "%.3f", n/1e9}')
    activating_gb=$(awk -v n="$activating" 'BEGIN{printf "%.3f", n/1e9}')
    deactivating_gb=$(awk -v n="$deactivating" 'BEGIN{printf "%.3f", n/1e9}')

    key_for_data="$NAME"
    if [[ -n "${NAME_TO_KEY[$NAME]}" ]]; then
      # уже є — дописуємо до ключа (для виводу)
      if [[ "${NAME_TO_KEY[$NAME]}" != "$s_key" ]]; then NAME_TO_KEY[$NAME]="${NAME_TO_KEY[$NAME]}+$s_key"; fi
    else
      NAME_TO_KEY[$NAME]="$s_key"
    fi

    if [[ -n "${data[$NAME]}" ]]; then
      IFS=":" read -r count oldname percent a d act <<< "${data[$NAME]}"
      new_count=$((count + 1))
      a=$(awk -v a="$a" -v b="$active_gb" 'BEGIN{printf "%.3f", a + b}')
      d=$(awk -v a="$d" -v b="$deactivating_gb" 'BEGIN{printf "%.3f", a + b}')
      act=$(awk -v a="$act" -v b="$activating_gb" 'BEGIN{printf "%.3f", a + b}')
    else
      new_count=1
      a="$active_gb"
      d="$deactivating_gb"
      act="$activating_gb"
    fi

    percent=$(awk -v a="$a" -v b="$TOTAL_ACTIVE_STAKE" 'BEGIN {if(b==0) print 0; else printf "%.3f", 100 * a / b}')
    data["$NAME"]="$new_count:$NAME:$percent:$a:$d:$act"

    USED_STAKE_KEYS["$stake_pubkey"]=1
  done
done




# processed=0
# start_time=$(date +%s)

# ➕ Фаза 2: WITHDRAWER KEY обробка
for w_key in "${!INDEX_BY_WTHDR[@]}"; do

#   ((processed++))
#   if (( processed % 10 == 0 )); then
#     current_time=$(date +%s)
#     elapsed=$((current_time - start_time))
#     total=${#INDEX_BY_WTHDR[@]}
# 
#     elapsed_fmt=$(printf '%02d:%02d' $((elapsed/60)) $((elapsed%60)))
#     if (( processed > 0 )); then
#       estimated_total_time=$(( (elapsed * total) / processed ))
#       remaining=$((estimated_total_time - elapsed))
#       remaining_fmt=$(printf '%02d:%02d' $((remaining/60)) $((remaining%60)))
#     else
#       remaining_fmt="??:??"
#     fi
# 
#     echo -e "${LIGHTGRAY}WTHDR KEY | Processed $processed / $total pairs... (${elapsed_fmt} elapsed, ~${remaining_fmt} remaining)${NOCOLOR}"
#   fi

  for stake_pubkey in "${ALL_STAKE_PUBKEYS[@]}"; do
    [[ -n "${USED_STAKE_KEYS[$stake_pubkey]}" ]] && continue
    [[ "${STAKE_ACCOUNT_WITHDRAWER[$stake_pubkey]}" != "$w_key" ]] && continue

    index="${INDEX_BY_WTHDR[$w_key]}"
    case "$AGGREGATION_MODE" in
      pool) NAME="${STAKE_NAMES[$index]}" ;;
      group) NAME="${POOL_GROUPS[$index]:-UNKNOWN}" ;;
      category) NAME="${POOL_CATEGORIES[$index]:-UNKNOWN}" ;;
    esac

    [[ -z "$NAME" ]] && continue

    active=${STAKE_ACCOUNT_ACTIVE[$stake_pubkey]}
    activating=${STAKE_ACCOUNT_ACTIVATING[$stake_pubkey]}
    deactivating=${STAKE_ACCOUNT_DEACTIVATING[$stake_pubkey]}

    active_gb=$(awk -v n="$active" 'BEGIN{printf "%.3f", n/1e9}')
    activating_gb=$(awk -v n="$activating" 'BEGIN{printf "%.3f", n/1e9}')
    deactivating_gb=$(awk -v n="$deactivating" 'BEGIN{printf "%.3f", n/1e9}')

    # Агрегація ключів
    if [[ -n "${NAME_TO_KEY[$NAME]}" ]]; then
      if [[ ! "${NAME_TO_KEY[$NAME]}" =~ (^|[+])${w_key}($|[+]) ]]; then
        NAME_TO_KEY[$NAME]="${NAME_TO_KEY[$NAME]}+$w_key"
      fi
    else
      NAME_TO_KEY[$NAME]="$w_key"
    fi

    if [[ -n "${data[$NAME]}" ]]; then
      IFS=":" read -r count oldname percent a d act <<< "${data[$NAME]}"
      new_count=$((count + 1))
      a=$(awk -v a="$a" -v b="$active_gb" 'BEGIN{printf "%.3f", a + b}')
      d=$(awk -v a="$d" -v b="$deactivating_gb" 'BEGIN{printf "%.3f", a + b}')
      act=$(awk -v a="$act" -v b="$activating_gb" 'BEGIN{printf "%.3f", a + b}')
    else
      new_count=1
      a="$active_gb"
      d="$deactivating_gb"
      act="$activating_gb"
    fi

    percent=$(awk -v a="$a" -v b="$TOTAL_ACTIVE_STAKE" 'BEGIN {if(b==0) print 0; else printf "%.3f", 100 * a / b}')
    data["$NAME"]="$new_count:$NAME:$percent:$a:$d:$act"

    USED_STAKE_KEYS["$stake_pubkey"]=1
  done
done


# processed=0
# start_time=$(date +%s)

# ➕ Фаза 3: інші (OTHER)
UNUSED_STAKE_KEYS=()
for stake_pubkey in "${ALL_STAKE_PUBKEYS[@]}"; do
    
# ((processed++))
# if (( processed % 1000 == 0 )); then
#   current_time=$(date +%s)
#   elapsed=$((current_time - start_time))
#   total=${#ALL_STAKE_PUBKEYS[@]}
# 
#   # Форматований час, що минув
#   elapsed_fmt=$(printf '%02d:%02d' $((elapsed/60)) $((elapsed%60)))
# 
#   # Оцінка часу до кінця (на основі середньої швидкості)
#   if (( processed > 0 )); then
# 	estimated_total_time=$(( (elapsed * total) / processed ))
# 	remaining=$((estimated_total_time - elapsed))
# 	remaining_fmt=$(printf '%02d:%02d' $((remaining/60)) $((remaining%60)))
#   else
# 	remaining_fmt="??:??"
#   fi
# 
#   echo -e "${LIGHTGRAY}OTHER KEY | Processed $processed / $total pairs... (${elapsed_fmt} elapsed, ~${remaining_fmt} remaining)${NOCOLOR}"
# fi

  [[ -z "${USED_STAKE_KEYS[$stake_pubkey]}" ]] && UNUSED_STAKE_KEYS+=("$stake_pubkey")
done


if (( ${#UNUSED_STAKE_KEYS[@]} > 0 )); then
  UNUSED_KEYS_FILE=$(mktemp "/tmp/unused_keys_$(date +%s%N)_XXXXXX.json")
  printf '%s\n' "${UNUSED_STAKE_KEYS[@]}" | jq -R . | jq -s . > "$UNUSED_KEYS_FILE"

  OTHER_SUMS=$(jq -r --slurpfile keys "$UNUSED_KEYS_FILE" '
    [ .[] | select(.stakePubkey as $key | $keys[0] | index($key)) ] |
    [
      ([.[].activeStake // 0] | add) / 1e9,
      ([.[].deactivatingStake // 0] | add) / 1e9,
      ([.[].activatingStake // 0] | add) / 1e9,
      length
    ] | @tsv
  ' "$ALL_MY_STAKES_FILE")

  rm -f "$UNUSED_KEYS_FILE"

  read -r a d act count <<< "$OTHER_SUMS"
  percent=$(awk -v a="$a" -v b="$TOTAL_ACTIVE_STAKE" 'BEGIN {if(b==0) print 0; else printf "%.3f", 100 * a / b}')
  data["OTHER"]="$count:OTHER:$percent:$a:$d:$act"

  for stake_pubkey in "${UNUSED_STAKE_KEYS[@]}"; do
    USED_STAKE_KEYS["$stake_pubkey"]=1
  done
fi





echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"

echo -e "${UNDERLINE}Key Authority\t\t\t\t\tCount\t${LIGHTPURPLE}${UNDERLINE}Info\t\t\t${LIGHTBLUE}${UNDERLINE}Percent\t\t${CYAN}${UNDERLINE}Active Stake\t${RED}${UNDERLINE}Deactivating\t${GREEN}${UNDERLINE}Activating${NOCOLOR}"


# Виклик функції для сортування за вибраним стовпчиком (наприклад, за Active Stake)
sort_data "${SORTING_CRITERIAS[@]}"


echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"

percent=$(printf "%.0f%%" "100")

# Уникнення експоненційної нотації та обрізка .000
[[ "$TOTAL_ACTIVE_STAKE" =~ ^0(\.0+)?$ ]] && TOTAL_ACTIVE_STAKE="0" || TOTAL_ACTIVE_STAKE=$(printf "%.3f" "$TOTAL_ACTIVE_STAKE")
[[ "$ACTIVATING_STAKE" =~ ^0(\.0+)?$ ]] && ACTIVATING_STAKE="0" || ACTIVATING_STAKE=$(printf "%.3f" "$ACTIVATING_STAKE")
[[ "$DEACTIVATING_STAKE" =~ ^0(\.0+)?$ ]] && DEACTIVATING_STAKE="0" || DEACTIVATING_STAKE=$(printf "%.3f" "$DEACTIVATING_STAKE")



printf "%-47s %-7d %-23s ${LIGHTBLUE}%-15s${NOCOLOR} ${CYAN}%-15s${NOCOLOR} ${RED}%-15s${NOCOLOR} ${GREEN}%-15s${NOCOLOR}\n" \
  "TOTAL:" "$TOTAL_ACTIVE_STAKE_COUNT" "" "$percent" "$TOTAL_ACTIVE_STAKE" "$DEACTIVATING_STAKE" "$ACTIVATING_STAKE"



  current_time=$(date +%s)
  elapsed=$((current_time - start_time))
  elapsed_fmt=$(printf '%02d:%02d' $((elapsed/60)) $((elapsed%60)))
  echo -e "${LIGHTGRAY}----------(${elapsed_fmt} elapsed----------${NOCOLOR}"


echo -e "${NOCOLOR}"

