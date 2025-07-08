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
YELLOW='\033[1;33m'
LIGHTPURPLE='\033[1;35m'
LIGHTBLUE='\033[1;34m'
UNDERLINE='\033[4m'
NOCOLOR='\033[0m'

declare -A data

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
    	
    # Швидка перевірка дублікатів
    for key in "${DONE_STAKES_REF[@]}"; do
        [[ "$KEY_S_TO_CHECK" == "$key" || "$KEY_W_TO_CHECK" == "$key" ]] && return 1
    done
    	
	RETURN_INFO=""
	FOUND_S="W"
	KEY_RESULT="\t"
	
	for j in "${!STAKE_AUTHORITY[@]}"; do
	  if [[ "$KEY_S_TO_CHECK" == "${STAKE_AUTHORITY[$j]}" ]]; then
		case "$AGGREGATION_MODE" in
		  pool) RETURN_INFO="${STAKE_AUTH_NAMES[$j]}" ;;
		  group) RETURN_INFO="${POOL_AUTH_GROUPS[$j]:-UNKNOWN}" ;;
		  category) RETURN_INFO="${POOL_AUTH_CATEGORIES[$j]:-UNKNOWN}" ;;
		esac
		FOUND_S="S"
		KEY_RESULT="$KEY_S_TO_CHECK"
		break
	  fi
	done
	
	if [[ "$FOUND_S" == "W" ]]; then
	  for k in "${!STAKE_WTHDR[@]}"; do
		if [[ "$KEY_W_TO_CHECK" == "${STAKE_WTHDR[$k]}" ]]; then
		  case "$AGGREGATION_MODE" in
			pool) RETURN_INFO="${STAKE_NAMES[$k]}" ;;
			group) RETURN_INFO="${POOL_GROUPS[$k]:-UNKNOWN}" ;;
			category) RETURN_INFO="${POOL_CATEGORIES[$k]:-UNKNOWN}" ;;
		  esac
		  KEY_RESULT="$KEY_W_TO_CHECK"
		  break
		fi
	  done
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




ALL_MY_STAKES=$(retry_command "solana ${SOLANA_CLUSTER} stakes ${YOUR_VOTE_ACCOUNT}" 10 "" false)


TOTAL_ACTIVE_STAKE=$(echo "$ALL_MY_STAKES" | awk '/Active Stake:/ {gsub("Active Stake: ", "", $0); gsub(" SOL", "", $0); sum += $1} END {printf "%.2f\n", sum}')
TOTAL_STAKE_COUNT=`echo -e "${ALL_MY_STAKES}" | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | bc | wc -l`

ACTIVATING_STAKE=$(echo "$ALL_MY_STAKES" | awk '/Activating Stake:/ {gsub("Activating Stake: ", "", $0); gsub(" SOL", "", $0); sum += $1} END {printf "%.2f\n", sum}')
ACTIVATING_STAKE_COUNT=`echo -e "${ALL_MY_STAKES}" | grep 'Activating Stake: ' | sed 's/Activating Stake: //g' | sed 's/ SOL//g' | bc | wc -l`

DEACTIVATING_STAKE=$(echo "$ALL_MY_STAKES" | awk '
{
  if (tolower($0) ~ /deactivates/) {
    if (prev ~ /Active Stake:/) {
      gsub("Active Stake: ", "", prev)
      gsub(" SOL", "", prev)
      sum += prev
    }
  }
  prev = $0
}
END {
  printf "%.2f\n", sum
}')
DEACTIVATING_STAKE_COUNT=`echo -e "${ALL_MY_STAKES}" | grep -B1 -i 'deactivates' | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | bc | wc -l`

TOTAL_ACTIVE_STAKE_COUNT=`echo "${TOTAL_STAKE_COUNT:-0} ${ACTIVATING_STAKE_COUNT:-0}" | awk '{print $1 - $2}' | bc`




mapfile -t ALL_STAKERS_KEYS_PAIRS < <(
  echo "$ALL_MY_STAKES" | grep -E -B1 "Withdraw" |
  grep -oP "(?<=Stake Authority: ).*|(?<=Withdraw Authority: ).*" |
  paste -d '+' - - | sort -u
)

echo -e "${DARKGRAY}All Stakers of $YOUR_VOTE_ACCOUNT | Epoch ${THIS_EPOCH} ${CLUSTER_NAME} | Aggregation: ${AGGREGATION_MODE^^}${NOCOLOR}"


OTHER_count=0
OTHER_percent=0
OTHER_active=0
OTHER_deactivating=0
OTHER_activating=0


DONE_STAKES=""
for i in "${ALL_STAKERS_KEYS_PAIRS[@]}"; do
    RES=$(check_key_pair "$DONE_STAKES" "$i")
	if [[ "$RES" == "" ]]; then
        continue
    fi
	
	KEY_TYPE_NAME=$(echo $RES | cut -d'^' -f1)
	DONE_STAKES=$(echo $RES | cut -d'^' -f2)
	
	KEY=$(echo $KEY_TYPE_NAME | cut -d' ' -f1)
	TYPE=$(echo $KEY_TYPE_NAME | cut -d' ' -f2)
	NAME=$(echo $KEY_TYPE_NAME | cut -d' ' -f3)
	
	# чи відомий пул (має ім’я)
	if [[ -z "$NAME" || "$NAME" == "\\t" || "$NAME" == "" ]]; then
		# це OTHER
		((OTHER_count+=count))
		
		active=$(echo "$ALL_MY_STAKES" | grep -B7 -E $KEY | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | bc | awk '{n+=0+$1+0}; END{print 0+n+0}')
		deactivating=$(echo "$ALL_MY_STAKES" | grep -B7 -E $KEY | grep -B1 -i 'deactivates' | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | bc | awk '{n+=0+$1+0}; END{print 0+n+0}')
		activating=$(echo "$ALL_MY_STAKES" | grep -B7 -E $KEY | grep 'Activating Stake' | sed 's/Activating Stake: //g' | sed 's/ SOL//g' | bc | awk '{n+=0+$1+0}; END{print 0+n+0}')
	
		OTHER_active=$(echo "$OTHER_active + $active" | bc)
		OTHER_deactivating=$(echo "$OTHER_deactivating + $deactivating" | bc)
		OTHER_activating=$(echo "$OTHER_activating + $activating" | bc)
	
		continue  # пропускаємо решту, не додаємо до data[]
	fi
	
	# Визначення значення count
    count=$(echo "$ALL_MY_STAKES" | grep -B7 -E $KEY | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | wc -l)

	if [[ "$AGGREGATION_MODE" == "group" || "$AGGREGATION_MODE" == "category" ]]; then
		key_for_data="$NAME"
	else
		key_for_data="$KEY"
	fi

	# Отримуємо попередні значення, якщо є
	if [[ -n "${data[$key_for_data]}" ]]; then
		IFS=':' read -r prev_count prev_name prev_percent prev_active prev_deactivating prev_activating <<< "${data[$key_for_data]}"
	else
		prev_count=0
		prev_percent=0
		prev_active=0
		prev_deactivating=0
		prev_activating=0
	fi
	
	# Отримуємо нові значення для цього ключа
	curr_count=$count
	curr_active=$(echo "$ALL_MY_STAKES" | grep -B7 -E "$KEY" | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | awk '{n+=0+$1+0}; END{print 0+n+0}')
	curr_deactivating=$(echo "$ALL_MY_STAKES" | grep -B7 -E "$KEY" | grep -B1 -i 'deactivates' | grep 'Active Stake' | sed 's/Active Stake: //g' | sed 's/ SOL//g' | awk '{n+=0+$1+0}; END{print 0+n+0}')
	curr_activating=$(echo "$ALL_MY_STAKES" | grep -B7 -E "$KEY" | grep 'Activating Stake' | sed 's/Activating Stake: //g' | sed 's/ SOL//g' | awk '{n+=0+$1+0}; END{print 0+n+0}')
	
	# Сумуємо нові й попередні
	total_count=$((prev_count + curr_count))
	total_active=$(echo "$prev_active + $curr_active" | bc)
	total_deactivating=$(echo "$prev_deactivating + $curr_deactivating" | bc)
	total_activating=$(echo "$prev_activating + $curr_activating" | bc)
	percent=$(echo "scale=3; 100 * $total_active / $TOTAL_ACTIVE_STAKE" | bc)
	
	# Записуємо у форматі (truncate до 7 символів)
	data["$key_for_data"]=$total_count:$NAME:$(
		echo "$percent" | sed -r 's/^(.{7}).*$/\1/'
	):$(
		echo "$total_active" | sed -r 's/^(.{7}).*$/\1/'
	):$(
		echo "$total_deactivating" | sed -r 's/^(.{7}).*$/\1/'
	):$(
		echo "$total_activating" | sed -r 's/^(.{7}).*$/\1/'
	)


done

OTHER_percent=$(echo "scale=3; 100 * $OTHER_active / $TOTAL_ACTIVE_STAKE" | bc)

data["OTHER"]=$OTHER_count:OTHER:$(
    echo "$OTHER_percent" | sed -r 's/^(.{7}).+$/\1/'
):$(
    echo "$OTHER_active" | sed -r 's/^(.{7}).+$/\1/'
):$(
    echo "$OTHER_deactivating" | sed -r 's/^(.{7}).+$/\1/'
):$(
    echo "$OTHER_activating" | sed -r 's/^(.{7}).+$/\1/'
)




echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"

echo -e "${UNDERLINE}Key Authority\t\t\t\t\tCount\t${LIGHTPURPLE}${UNDERLINE}Info\t\t\t${LIGHTBLUE}${UNDERLINE}Percent\t\t${CYAN}${UNDERLINE}Active Stake\t${RED}${UNDERLINE}Deactivating\t${GREEN}${UNDERLINE}Activating${NOCOLOR}"


# Виклик функції для сортування за вибраним стовпчиком (наприклад, за Active Stake)
sort_data "${SORTING_CRITERIAS[@]}"

#sort_data 4:DESC 6:DESC
#sort_data 6:DESC 4:DESC 1:DESC 3:ASC




echo -e "————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————————"

percent=$(printf "%.3f%%" "100")

printf "%-47s %-7d %-23s ${LIGHTBLUE}%-15s${NOCOLOR} ${CYAN}%-15s${NOCOLOR} ${RED}%-15s${NOCOLOR} ${GREEN}%-15s${NOCOLOR}\n" \
  "TOTAL:" "$TOTAL_ACTIVE_STAKE_COUNT" "" "$percent" "$TOTAL_ACTIVE_STAKE" "$DEACTIVATING_STAKE" "$ACTIVATING_STAKE"


echo -e "${NOCOLOR}"
