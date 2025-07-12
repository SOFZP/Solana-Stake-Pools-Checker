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

function check_key_pair () {
    local DONE_STAKES_REF=($1)
    local KEYS_PAIR="$2"

    local KEY_S_TO_CHECK="${KEYS_PAIR%%+*}"
    local KEY_W_TO_CHECK="${KEYS_PAIR##*+}"

    # 🔁 Avoid duplicate processing
    for key in "${DONE_STAKES_REF[@]}"; do
        [[ "$KEY_S_TO_CHECK" == "$key" || "$KEY_W_TO_CHECK" == "$key" ]] && return 1
    done

    local RETURN_INFO=""
    local FOUND_S="W"
    local KEY_RESULT="\t"

    # 🔍 Quick lookup by stake authority
    if [[ -n "${INDEX_BY_STAKE_AUTH[$KEY_S_TO_CHECK]}" ]]; then
        local j="${INDEX_BY_STAKE_AUTH[$KEY_S_TO_CHECK]}"
        case "$AGGREGATION_MODE" in
            pool) RETURN_INFO="${STAKE_AUTH_NAMES[$j]}" ;;
            group) RETURN_INFO="${POOL_AUTH_GROUPS[$j]:-UNKNOWN}" ;;
            category) RETURN_INFO="${POOL_AUTH_CATEGORIES[$j]:-UNKNOWN}" ;;
        esac
        FOUND_S="S"
        KEY_RESULT="$KEY_S_TO_CHECK"
    elif [[ -n "${INDEX_BY_WTHDR[$KEY_W_TO_CHECK]}" ]]; then
        local k="${INDEX_BY_WTHDR[$KEY_W_TO_CHECK]}"
        case "$AGGREGATION_MODE" in
            pool) RETURN_INFO="${STAKE_NAMES[$k]}" ;;
            group) RETURN_INFO="${POOL_GROUPS[$k]:-UNKNOWN}" ;;
            category) RETURN_INFO="${POOL_CATEGORIES[$k]:-UNKNOWN}" ;;
        esac
        KEY_RESULT="$KEY_W_TO_CHECK"
    fi

    local RETURN_KEY_TYPE_NAME=""
    if [[ -z "$RETURN_INFO" ]]; then
        RETURN_KEY_TYPE_NAME="$KEY_W_TO_CHECK W \t"
    else
        RETURN_KEY_TYPE_NAME="$KEY_RESULT $FOUND_S $RETURN_INFO"
    fi

    echo "${RETURN_KEY_TYPE_NAME}^${KEY_RESULT} ${DONE_STAKES_REF[*]}"
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
        
        # Уникнення експоненційної нотації та обрізка .000
		[[ "$active" =~ ^0(\.0+)?$ ]] && active="0" || active=$(printf "%.3f" "$active")
		[[ "$deactivating" =~ ^0(\.0+)?$ ]] && deactivating="0" || deactivating=$(printf "%.3f" "$deactivating")
		[[ "$activating" =~ ^0(\.0+)?$ ]] && activating="0" || activating=$(printf "%.3f" "$activating")

        printf "%-47s %-7d ${LIGHTPURPLE}%-23s${NOCOLOR} ${LIGHTBLUE}%-15s${NOCOLOR} ${CYAN}%-15s${NOCOLOR} ${RED}%-15s${NOCOLOR} ${GREEN}%-15s${NOCOLOR}\n" \
          "$key" "$count" "$info" "$percent" "$active" "$deactivating" "$activating"
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

# 🔄 Агрегуємо відразу все по staker+withdrawer
# AGG_JSON=$(echo "$ALL_MY_STAKES_JSON" | jq -c '
#   map(select(.staker != null and .withdrawer != null and .staker != "" and .withdrawer != ""))
#   | sort_by(.staker + "+" + .withdrawer)
#   | group_by(.staker + "+" + .withdrawer)
#   | map({
#       pair: (.[0].staker + "+" + .[0].withdrawer),
#       count: length,
#       active: (map(.activeStake // 0) | add / 1e9),
#       activating: (map(.activatingStake // 0) | add / 1e9),
#       deactivating: (map(.deactivatingStake // 0) | add / 1e9)
#     })
#   | reduce .[] as $item (
#       {}; . + { ($item.pair): {count: $item.count, active: $item.active, activating: $item.activating, deactivating: $item.deactivating} }
#     )
# ')

# AGG_JSON=$(echo "$ALL_MY_STAKES_JSON" | jq -c '
#   map(select(.staker != null and .withdrawer != null and .staker != "" and .withdrawer != ""))
#   | sort_by(.staker + "+" + .withdrawer)
#   | group_by(.staker + "+" + .withdrawer)
#   | map({
#       key: (.[0].staker + "+" + .[0].withdrawer),
#       value: {
#         count: length,
#         active: (map(.activeStake // 0) | add / 1e9),
#         activating: (map(.activatingStake // 0) | add / 1e9),
#         deactivating: (map(.deactivatingStake // 0) | add / 1e9)
#       }
#     })
#   | from_entries
# ')


# Кеш stake-аккаунтів
declare -A STAKES_BY_PAIR

while IFS=$'\t' read -r stake_key staker withdrawer active activating deactivating; do
  key_pair="${staker}+${withdrawer}"
  STAKES_BY_PAIR["$key_pair"]+="$active,$activating,$deactivating;"
done < <(jq -r '.[] | [.stakePubkey, .staker, .withdrawer, (.activeStake // 0), (.activatingStake // 0), (.deactivatingStake // 0)] | @tsv' <<< "$ALL_MY_STAKES_JSON")

mapfile -t ALL_STAKERS_KEYS_PAIRS < <(
  echo "$ALL_MY_STAKES_JSON" | jq -r '.[] | "\(.staker)+\(.withdrawer)"' | sort -u
)

# 
# # ⏩ Формуємо список пар ключів
# mapfile -t ALL_STAKERS_KEYS_PAIRS < <(
#   echo "$AGG_JSON" | jq -r 'keys[]'
# )




TOTAL_ACTIVE_STAKE=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[].activeStake // 0] | add / 1e9' | awk '{printf "%.3f\n", $1}')
TOTAL_STAKE_COUNT=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[] | select(.activeStake // 0 > 0)] | length')

ACTIVATING_STAKE=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[].activatingStake // 0] | add / 1e9' | awk '{printf "%.3f\n", $1}')
ACTIVATING_STAKE_COUNT=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[] | select(.activatingStake // 0 > 0)] | length')

DEACTIVATING_STAKE=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[].deactivatingStake // 0] | add / 1e9' | awk '{printf "%.3f\n", $1}')
DEACTIVATING_STAKE_COUNT=$(echo "$ALL_MY_STAKES_JSON" | jq '[.[] | select(.deactivatingStake // 0 > 0)] | length')

TOTAL_ACTIVE_STAKE_COUNT=$((TOTAL_STAKE_COUNT - ACTIVATING_STAKE_COUNT))


OTHER_count=0
OTHER_percent=0
OTHER_active=0
OTHER_deactivating=0
OTHER_activating=0

DONE_STAKES=""

declare -A STAKE_AUTH_NAMES_MAP
for ((i=0; i<${#STAKE_AUTHORITY[@]}; i++)); do
  STAKE_AUTH_NAMES_MAP["${STAKE_AUTHORITY[$i]}"]="${STAKE_AUTH_NAMES[$i]}"
done

declare -A POOL_AUTH_GROUPS_MAP
for ((i=0; i<${#STAKE_AUTHORITY[@]}; i++)); do
  POOL_AUTH_GROUPS_MAP["${STAKE_AUTHORITY[$i]}"]="${POOL_AUTH_GROUPS[$i]}"
done

declare -A POOL_AUTH_CATEGORIES_MAP
for ((i=0; i<${#STAKE_AUTHORITY[@]}; i++)); do
  POOL_AUTH_CATEGORIES_MAP["${STAKE_AUTHORITY[$i]}"]="${POOL_AUTH_CATEGORIES[$i]}"
done

# Попередня обробка всіх S-ключів напряму (до основного циклу)
for s_key in "${STAKE_AUTHORITY[@]}"; do
  stake_entries=$(echo "$ALL_MY_STAKES_JSON" | jq -c --arg key "$s_key" '.[] | select(.staker == $key)')

  count=0
  active=0
  deactivating=0
  activating=0

  while IFS= read -r stake; do
      s_active=$(echo "$stake" | jq '.activeStake // 0')
      s_deactivating=$(echo "$stake" | jq '.deactivatingStake // 0')
      s_activating=$(echo "$stake" | jq '.activatingStake // 0')

      [[ "$s_active" != "0" ]] && ((count++))
      active=$((active + s_active))
      deactivating=$((deactivating + s_deactivating))
      activating=$((activating + s_activating))
  done <<< "$stake_entries"

  # ⛔ Пропускаємо, якщо повністю порожній
  if [[ "$active" == "0" && "$deactivating" == "0" && "$activating" == "0" ]]; then
    continue
  fi

  active=$(awk -v n="$active" 'BEGIN{printf "%.3f", n/1e9}')
  deactivating=$(awk -v n="$deactivating" 'BEGIN{printf "%.3f", n/1e9}')
  activating=$(awk -v n="$activating" 'BEGIN{printf "%.3f", n/1e9}')

  case "$AGGREGATION_MODE" in
    pool) NAME="${STAKE_AUTH_NAMES_MAP[$s_key]}" ;;
    group) NAME="${POOL_AUTH_GROUPS_MAP[$s_key]:-UNKNOWN}" ;;
    category) NAME="${POOL_AUTH_CATEGORIES_MAP[$s_key]:-UNKNOWN}" ;;
  esac

  percent=$(awk -v a="$active" -v b="$TOTAL_ACTIVE_STAKE" 'BEGIN {if(b==0) print 0; else printf "%.3f", 100 * a / b}')

  data["$s_key"]=$count:$NAME:$(
    echo "$percent" | sed -r 's/^(.{12}).*$/\1/'
  ):$(
    echo "$active" | sed -r 's/^(.{12}).*$/\1/'
  ):$(
    echo "$deactivating" | sed -r 's/^(.{12}).*$/\1/'
  ):$(
    echo "$activating" | sed -r 's/^(.{12}).*$/\1/'
  )

  DONE_STAKES+=" $s_key"
done


processed=0
start_time=$(date +%s)

for i in "${ALL_STAKERS_KEYS_PAIRS[@]}"; do

	((processed++))
	if (( processed % 100 == 0 )); then
	  current_time=$(date +%s)
	  elapsed=$((current_time - start_time))
	  total=${#ALL_STAKERS_KEYS_PAIRS[@]}
	
	  # Форматований час, що минув
	  elapsed_fmt=$(printf '%02d:%02d' $((elapsed/60)) $((elapsed%60)))
	
	  # Оцінка часу до кінця (на основі середньої швидкості)
	  if (( processed > 0 )); then
		estimated_total_time=$(( (elapsed * total) / processed ))
		remaining=$((estimated_total_time - elapsed))
		remaining_fmt=$(printf '%02d:%02d' $((remaining/60)) $((remaining%60)))
	  else
		remaining_fmt="??:??"
	  fi
	
	  echo -e "${LIGHTGRAY}Processed $processed / $total pairs... (${elapsed_fmt} elapsed, ~${remaining_fmt} remaining)${NOCOLOR}"
	fi



	if [[ -n "${CHECKED_KEYS[$i]}" ]]; then
	  RES="${CHECKED_KEYS[$i]}"
	else
	  RES=$(check_key_pair "$DONE_STAKES" "$i")
	  [[ -z "$RES" ]] && continue
	  CHECKED_KEYS["$i"]="$RES"
	fi

    KEY_TYPE_NAME=$(echo "$RES" | cut -d'^' -f1)
    DONE_STAKES=$(echo "$RES" | cut -d'^' -f2)

    KEY=$(echo "$KEY_TYPE_NAME" | cut -d' ' -f1)
    TYPE=$(echo "$KEY_TYPE_NAME" | cut -d' ' -f2)
    NAME=$(echo "$KEY_TYPE_NAME" | cut -d' ' -f3)

# count=$(jq -r --arg pair "$i" '.[$pair].count' <<< "$AGG_JSON")
# active=$(jq -r --arg pair "$i" '.[$pair].active' <<< "$AGG_JSON")
# activating=$(jq -r --arg pair "$i" '.[$pair].activating' <<< "$AGG_JSON")
# deactivating=$(jq -r --arg pair "$i" '.[$pair].deactivating' <<< "$AGG_JSON")

    stake_values="${STAKES_BY_PAIR[$i]}"
    [[ -z "$stake_values" ]] && continue
    
# ВИВЕСТИ ПО БОНДУ ЯК ДЕБАГ

    count=$(echo "$stake_values" | tr ';' '\n' | grep -v '^$' | wc -l)
    active=$(echo "$stake_values" | tr ';' '\n' | cut -d',' -f1 | awk '{sum+=$1} END{printf "%.3f", sum/1e9}')
    activating=$(echo "$stake_values" | tr ';' '\n' | cut -d',' -f2 | awk '{sum+=$1} END{printf "%.3f", sum/1e9}')
    deactivating=$(echo "$stake_values" | tr ';' '\n' | cut -d',' -f3 | awk '{sum+=$1} END{printf "%.3f", sum/1e9}')

    if [[ -z "$NAME" || "$NAME" == "\\t" || "$NAME" == "" ]]; then
        ((OTHER_count+=count))
        OTHER_active=$(awk -v a="$OTHER_active" -v b="$active" 'BEGIN{printf "%.3f", a + b}')
        OTHER_deactivating=$(awk -v a="$OTHER_deactivating" -v b="$deactivating" 'BEGIN{printf "%.3f", a + b}')
        OTHER_activating=$(awk -v a="$OTHER_activating" -v b="$activating" 'BEGIN{printf "%.3f", a + b}')
        continue
    fi

    if [[ "$AGGREGATION_MODE" == "group" || "$AGGREGATION_MODE" == "category" ]]; then
        key_for_data="$NAME"
    else
        key_for_data="$KEY"
    fi

    if [[ -n "${data[$key_for_data]}" ]]; then
        IFS=':' read -r prev_count prev_name prev_percent prev_active prev_deactivating prev_activating <<< "${data[$key_for_data]}"
    else
        prev_count=0
        prev_percent=0
        prev_active=0
        prev_deactivating=0
        prev_activating=0
    fi

    curr_count=$count
    curr_active=$active
    curr_deactivating=$deactivating
    curr_activating=$activating

    total_count=$((prev_count + curr_count))
    total_active=$(awk -v a="$prev_active" -v b="$curr_active" 'BEGIN{printf "%.3f", a + b}')
    total_deactivating=$(awk -v a="$prev_deactivating" -v b="$curr_deactivating" 'BEGIN{printf "%.3f", a + b}')
    total_activating=$(awk -v a="$prev_activating" -v b="$curr_activating" 'BEGIN{printf "%.3f", a + b}')
    percent=$(awk -v a="$total_active" -v b="$TOTAL_ACTIVE_STAKE" 'BEGIN {if(b==0) print 0; else printf "%.3f", 100 * a / b}')

    data["$key_for_data"]=$total_count:$NAME:$(
        echo "$percent" | sed -r 's/^(.{12}).*$/\1/'
    ):$(
        echo "$total_active" | sed -r 's/^(.{12}).*$/\1/'
    ):$(
        echo "$total_deactivating" | sed -r 's/^(.{12}).*$/\1/'
    ):$(
        echo "$total_activating" | sed -r 's/^(.{12}).*$/\1/'
    )
done


OTHER_percent=$(awk -v a="$OTHER_active" -v b="$TOTAL_ACTIVE_STAKE" 'BEGIN{if(b==0) print 0; else printf "%.3f", 100 * a / b}')

data["OTHER"]=$OTHER_count:OTHER:$(
    echo "$OTHER_percent" | sed -r 's/^(.{12}).+$/\1/'
):$(
    echo "$OTHER_active" | sed -r 's/^(.{12}).+$/\1/'
):$(
    echo "$OTHER_deactivating" | sed -r 's/^(.{12}).+$/\1/'
):$(
    echo "$OTHER_activating" | sed -r 's/^(.{12}).+$/\1/'
)




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


echo -e "${NOCOLOR}"
