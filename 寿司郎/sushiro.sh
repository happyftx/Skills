#!/usr/bin/env bash
# sushiro — query Sushiro China queue/wait status via wechat-mini-program backend.
# Enhanced with UX features: Wait estimation, Velocity tracking, Notifications, and Dashboard.

set -euo pipefail

BASE="https://crm-cn-prd.sushiro.com.cn/wechat/api/2.0"
TOKEN="${SUSHIRO_TOKEN:-4OI44O844Kv44Oz5qSc6Ki855So77yad2VjaGF05YWx6YCa4}"
REFERER="https://servicewechat.com/wx7ac31ef6c073a7ed/159/page-frame.html"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"

_get() {
  curl -sS -m 15 --fail-with-body \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Referer: ${REFERER}" \
    -H "User-Agent: ${UA}" \
    -H "Accept: */*" \
    "${BASE}/$1"
}

_die() { echo "Error: $*" >&2; exit 1; }

# Original Commands
cmd_stores() {
  local is_json=0 city="" waiting=0 near="" limit=9999
  for arg in "$@"; do
    case $arg in
      --json) is_json=1 ;;
      --waiting) waiting=1 ;;
      --city=*) city="${arg#*=}" ;;
      --near=*) near="${arg#*=}" ;;
      --limit=*) limit="${arg#*=}" ;;
    esac
  done

  local path="stores?numresults=${limit}"
  if [[ -n "$near" ]]; then
    local lat="${near%%,*}"; local lng="${near##*,}"
    path="stores?latitude=${lat}&longitude=${lng}&numresults=${limit}"
  fi

  local raw
  raw=$(_get "$path") || _die "Failed to fetch stores."

  if [[ $is_json -eq 1 ]]; then
    echo "$raw" | jq '.'
    return
  fi

  printf "%-5s %-7s %-5s %-4s %-12s %s\n" "WAIT" "STATUS" "ID" "CITY" "AREA" "NAME"
  echo "$raw" | jq -r --arg city "$city" --argjson waiting "$waiting" '
    .[] | select($city == "" or .nameKana == $city) |
    select($waiting == 0 or (.wait > 0)) |
    [ (.wait // 0), .storeStatus, .id, .nameKana, .area, .name ] | @tsv
  ' | while IFS=$'\t' read -r wait status id c a n; do
    printf "%-5s %-7s %-5s %-4s %-12s %s\n" "$wait" "$status" "$id" "$c" "$a" "$n"
  done
}

cmd_store() {
  local id="$1" is_json=0
  [[ "${2:-}" == "--json" ]] && is_json=1

  local raw
  raw=$(_get "getStoreById?storeId=${id}") || _die "Failed to fetch store ${id}."

  if [[ $is_json -eq 1 ]]; then
    echo "$raw" | jq '.'
  else
    echo "$raw" | jq -r '
      "Store: \(.name)\n" +
      "ID: \(.id)\n" +
      "Status: \(.storeStatus)\n" +
      "Waiting groups: \(.wait // 0)\n" +
      "Wait time cap: \(.waitTimeCap // 0) mins\n" +
      "Address: \(.address)\n"
    '
  fi
}

cmd_wait() {
  local id="$1"
  local raw
  raw=$(_get "getStoreById?storeId=${id}") || _die "Fetch failed."
  local wait
  wait=$(echo "$raw" | jq -r '.wait // 0')
  echo "$wait"
}

cmd_search() {
  local kw="$1"
  local raw
  raw=$(_get "stores") || _die "Fetch failed."
  
  printf "%-5s %-7s %-5s %-4s %-12s %s\n" "WAIT" "STATUS" "ID" "CITY" "AREA" "NAME"
  echo "$raw" | jq -r --arg kw "$kw" '
    .[] | select(.name + .nameKana + .area + .address | contains($kw)) |
    [ (.wait // 0), .storeStatus, .id, .nameKana, .area, .name ] | @tsv
  ' | while IFS=$'\t' read -r wait status id c a n; do
    printf "%-5s %-7s %-5s %-4s %-12s %s\n" "$wait" "$status" "$id" "$c" "$a" "$n"
  done
}

cmd_areas() {
  local is_json=0
  [[ "${1:-}" == "--json" ]] && is_json=1
  local raw
  raw=$(_get "areas") || _die "Fetch failed."
  
  if [[ $is_json -eq 1 ]]; then
    echo "$raw" | jq '.'
  else
    echo "$raw" | jq -r '.[].name'
  fi
}

cmd_summary() {
  local raw
  raw=$(_get "stores") || _die "Fetch failed."
  echo "$raw" | jq '
    reduce .[] as $s (
      {};
      .[$s.nameKana] |= (
        .stores += 1 |
        .waiting += ($s.wait // 0) |
        if $s.storeStatus == "OPEN" then .open += 1 else . end
      )
    ) | 
    to_entries | map({city: .key} + .value) | sort_by(-.waiting) |
    {
      total: (map(.stores) | add),
      open: (map(.open) | add),
      waiting_stores: map(select(.waiting > 0) | 1) | length,
      total_wait_groups: (map(.waiting) | add),
      by_city: .
    }
  '
}

# --- NEW UX ENHANCEMENT COMMANDS ---

cmd_estimate() {
  local id="$1" seat_type="${2:-table}"
  local raw wait_groups multiplier est_minutes store_name
  raw=$(_get "getStoreById?storeId=${id}") || _die "Fetch failed."
  wait_groups=$(echo "$raw" | jq -r '.wait // 0')
  store_name=$(echo "$raw" | jq -r '.name')

  if [[ "$seat_type" == "counter" ]]; then
    multiplier=3
  else
    multiplier=5
  fi
  
  est_minutes=$((wait_groups * multiplier))
  
  echo "🍣 门店: $store_name"
  echo "👥 当前排队: $wait_groups 桌"
  if [[ $wait_groups -eq 0 ]]; then
    echo "⚡ 预估等待: 无需排队！"
  else
    echo "⏳ 预估等待: 约 $est_minutes 分钟 (基于 ${seat_type} 平均翻台率计算)"
  fi
}

cmd_track() {
  local id="$1" interval="${2:-60}"
  local prev_wait="" store_name=""
  echo "开始追踪门店排队速度... 每 ${interval} 秒刷新一次。按 Ctrl+C 停止。"
  
  while true; do
    local raw=$(_get "getStoreById?storeId=${id}")
    local current_wait=$(echo "$raw" | jq -r '.wait // 0')
    local current_time=$(date +%H:%M:%S)
    
    if [[ -z "$store_name" ]]; then
      store_name=$(echo "$raw" | jq -r '.name')
      echo "📍 门店: $store_name"
    fi

    if [[ -n "$prev_wait" ]]; then
      local delta=$((prev_wait - current_wait))
      local speed_msg=""
      if (( delta > 2 )); then speed_msg="🚀 很快"
      elif (( delta > 0 )); then speed_msg="🚶 正常"
      elif (( delta == 0 )); then speed_msg="🛑 卡住了"
      else speed_msg="📈 人变多了"
      fi
      
      echo "[$current_time] 剩余: $current_wait 桌 (过去 ${interval}s 消化了 $delta 桌 | 速度: $speed_msg)"
    else
      echo "[$current_time] 初始: $current_wait 桌"
    fi
    
    prev_wait="$current_wait"
    sleep "$interval"
  done
}

cmd_alert() {
  local id="$1" threshold="$2"
  local raw store_name
  raw=$(_get "getStoreById?storeId=${id}") || _die "Fetch failed."
  store_name=$(echo "$raw" | jq -r '.name')
  
  echo "🚨 已开启提醒。当 [$store_name] 排队小于等于 $threshold 桌时，将推送通知。"
  
  if [[ -z "${BARK_KEY:-}" ]]; then
    echo "💡 提示: 您未配置 BARK_KEY 环境变量，将仅使用 Mac 系统级弹窗提醒。"
    echo "如果要发送到 iPhone，请在运行前设置: export BARK_KEY='您的iOS_Bark_Key'"
  else
    echo "📱 iOS Bark 推送已就绪！"
  fi

  while true; do
    local current_wait=$(_get "getStoreById?storeId=${id}" | jq -r '.wait // 0')
    
    if [[ "$current_wait" -le "$threshold" ]]; then
      local msg="快到了！[$store_name] 仅剩 $current_wait 桌，请及时前往就餐。"
      
      # macOS Native Notification
      osascript -e "display notification \"$msg\" with title \"🍣 寿司郎叫号提醒\" sound name \"Glass\""
      
      # iOS Bark Push Notification
      if [[ -n "${BARK_KEY:-}" ]]; then
        local title_encoded=$(jq -rn --arg x "寿司郎提醒" '$x|@uri')
        local body_encoded=$(jq -rn --arg x "剩${current_wait}桌，速回门店" '$x|@uri')
        curl -s "https://api.day.app/${BARK_KEY}/${title_encoded}/${body_encoded}?sound=minuet" > /dev/null
      fi
      
      echo -e "\n⏰ $msg"
      exit 0
    fi
    
    if (( current_wait - threshold > 20 )); then
      sleep 60
    else
      sleep 20
    fi
  done
}

cmd_dash() {
  local id="$1" initial_groups="${2:-0}"
  
  if [[ "$initial_groups" -eq 0 ]]; then
    initial_groups=$(_get "getStoreById?storeId=${id}" | jq -r '.wait // 0')
    if [[ "$initial_groups" -eq 0 ]]; then
      _die "当前无需排队！"
    fi
  fi

  while true; do
    local raw=$(_get "getStoreById?storeId=${id}")
    local current_wait=$(echo "$raw" | jq -r '.wait // 0')
    local store_name=$(echo "$raw" | jq -r '.name')
    local current_time=$(date +%H:%M:%S)
    
    local percent=$(( (initial_groups - current_wait) * 100 / initial_groups ))
    [[ $percent -lt 0 ]] && percent=0
    [[ $percent -gt 100 ]] && percent=100

    printf "\033c"
    
    echo "======================================"
    echo "      🍣 寿司郎实时排队看板 🍣"
    echo "======================================"
    echo " 📍 门店: $store_name"
    echo " 🕒 更新: $current_time"
    echo " 🎫 您的起始桌数: $initial_groups 桌"
    echo " 👥 当前还剩:     $current_wait 桌"
    echo "--------------------------------------"
    
    printf " 进度: ["
    local filled=$((percent / 5))
    local empty=$((20 - filled))
    for ((i=0; i<filled; i++)); do printf "█"; done
    for ((i=0; i<empty; i++)); do printf "░"; done
    printf "] %d%%\n" "$percent"
    
    echo "======================================"
    echo " 按 Ctrl+C 退出面板"
    
    sleep 15
  done
}

cmd_raw() {
  _get "$1"
}

cmd_help() {
  cat <<HELP_EOF
sushiro — Sushiro China queue/wait status

Commands:
  stores [filters]         List all stores
  store <id>               Single store detail
  wait <id>                One-line wait count for a store
  search <keyword>         Search by name / area / city / address
  areas                    List all area names
  summary                  Aggregate stats by city

UX Enhancement Commands:
  estimate <id> [type]     预估等待时间 (type: table/counter，默认 table)
  track <id> [interval]    监控队伍消化速度 (默认60秒刷新)
  alert <id> <threshold>   弹窗/推送提醒 (当桌数小于等于 threshold 时)
  dash <id> [initial_wait] 渲染动态排队进度条面板

Examples:
  sushiro search 来福士
  sushiro estimate 3014 counter
  sushiro track 3014 30
  sushiro alert 3014 5
  sushiro dash 3014 45

Env:
  SUSHIRO_TOKEN   override the default Bearer token
  BARK_KEY        iOS Bark push notification key (for alert command)
HELP_EOF
}

if [[ $# -eq 0 ]]; then
  cmd_help
  exit 0
fi

CMD="$1"
shift

case "$CMD" in
  stores) cmd_stores "$@" ;;
  store) cmd_store "$@" ;;
  wait) cmd_wait "$@" ;;
  search) cmd_search "$@" ;;
  areas) cmd_areas "$@" ;;
  summary) cmd_summary "$@" ;;
  estimate) cmd_estimate "$@" ;;
  track) cmd_track "$@" ;;
  alert) cmd_alert "$@" ;;
  dash) cmd_dash "$@" ;;
  raw) cmd_raw "$@" ;;
  --help|-h|help) cmd_help ;;
  *) _die "Unknown command: $CMD" ;;
esac
