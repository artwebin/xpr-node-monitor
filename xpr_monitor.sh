#!/bin/bash

# ==============================================================================
# XPR Network Block Producer Monitoring Script
#
# Description: A comprehensive monitoring script for XPR nodes with
#              Telegram notifications and auto-restart capabilities.
# Author:      Artwebin Team
# Version:     2.0
# ==============================================================================

# --- Configuration and Initialization ---
set -o pipefail
CONFIG_FILE="/etc/xpr-monitor/config.conf"
LOG_FILE="/var/log/xpr-monitor.log"
SILENT_MODE=false

# --- Load Configuration ---
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "CRITICAL: Configuration file not found at $CONFIG_FILE. Exiting."
    exit 1
fi

# --- Default Values (if not set in config) ---
BP_NAME="${BP_NAME:-"MyXPRNode"}"
LOCAL_API="${LOCAL_API:-"http://127.0.0.1:8888"}"
API_URL="${API_URL:-"https://mainnet.api.xpr.network"}"
NODEOS_DIR="${NODEOS_DIR:-"/opt/xpr"}"
MAX_BLOCKS_BEHIND="${MAX_BLOCKS_BEHIND:-100}"
CPU_CRITICAL_THRESHOLD="${CPU_CRITICAL_THRESHOLD:-90}"
MEMORY_CRITICAL_THRESHOLD="${MEMORY_CRITICAL_THRESHOLD:-90}"
DISK_CRITICAL_THRESHOLD="${DISK_CRITICAL_THRESHOLD:-90}"
AUTO_RESTART_NODEOS="${AUTO_RESTART_NODEOS:-"true"}"
MAX_RESTART_ATTEMPTS="${MAX_RESTART_ATTEMPTS:-3}"
RESTART_STATE_FILE="${RESTART_STATE_FILE:-"/var/tmp/xpr_monitor_restart.state"}"
API_TIMEOUT="${API_TIMEOUT:-10}"

# --- Argument Parsing ---
if [ "$1" == "--silent" ]; then
    SILENT_MODE=true
    shift # Remove --silent from arguments
fi
CHECK_TYPE="${1:-basic}"


# --- Logging Function ---
log_message( ) {
    # Logs message to the log file.
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [$CHECK_TYPE] - $1" >> "$LOG_FILE"
}

# --- Telegram Notification Function ---
send_telegram() {
    local message="$1"
    local priority="$2" # INFO, WARNING, CRITICAL, SUCCESS

    # Skip sending non-critical notifications in silent mode
    if $SILENT_MODE && [ "$priority" != "CRITICAL" ]; then
        return
    fi

    case "$priority" in
        "CRITICAL") emoji="🚨" ;;
        "WARNING")  emoji="⚠️" ;;
        "INFO")     emoji="ℹ️" ;;
        "SUCCESS")  emoji="✅" ;;
        *)          emoji="📊" ;;
    esac

    local full_message=$(echo -e "🖥️ *$BP_NAME Monitor*\n\n$message\n\n_$(date '+%Y-%m-%d %H:%M:%S')_")

    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
        -d "chat_id=$CHAT_ID" \
        -d "text=$full_message" \
        -d "parse_mode=Markdown" > /dev/null 2>&1

    log_message "Telegram notification sent ($priority ): $message"
}

# --- Health Check Functions ---

check_nodeos_process() {
    if pgrep -x "nodeos" > /dev/null; then
        return 0 # Running
    else
        return 1 # Stopped
    fi
}

check_local_api() {
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" "$LOCAL_API/v1/chain/get_info" 2>/dev/null)
    if [ $? -eq 0 ] && echo "$response" | jq -e '.head_block_num' > /dev/null; then
        echo "$response" | jq '.head_block_num'
        return 0
    else
        return 1
    fi
}

check_public_api() {
    local response
    response=$(curl -s --max-time "$API_TIMEOUT" "$API_URL/v1/chain/get_info" 2>/dev/null)
    if [ $? -eq 0 ] && echo "$response" | jq -e '.head_block_num' > /dev/null; then
        echo "$response" | jq '.head_block_num'
        return 0
    else
        return 1
    fi
}

check_sync_status() {
    local local_block public_block
    local_block=$(check_local_api)
    public_block=$(check_public_api)

    if [ -n "$local_block" ] && [ -n "$public_block" ]; then
        local diff=$((public_block - local_block))
        if [ "$diff" -lt "$MAX_BLOCKS_BEHIND" ]; then
            return 0 # Synced
        else
            log_message "WARNING: Node is $diff blocks behind (Threshold: $MAX_BLOCKS_BEHIND)."
            send_telegram "⚠️ *Node is $diff blocks behind* the network." "WARNING"
            return 1 # Out of sync
        fi
    else
        log_message "ERROR: Could not determine sync status. One or both APIs failed."
        send_telegram "⚠️ Could not determine sync status. API check failed." "WARNING"
        return 1 # API error
    fi
}

check_system_resources() {
    local cpu_usage mem_usage disk_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    mem_usage=$(free | grep Mem | awk '{printf "%.0f", $3/$2 * 100.0}')
    disk_usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')

    if (( $(echo "$cpu_usage > $CPU_CRITICAL_THRESHOLD" | bc -l) )); then
        log_message "CRITICAL: High CPU usage at ${cpu_usage}%."
        send_telegram "🚨 High CPU usage detected: *${cpu_usage}%*." "CRITICAL"
    fi
    if [ "$mem_usage" -gt "$MEMORY_CRITICAL_THRESHOLD" ]; then
        log_message "CRITICAL: High Memory usage at ${mem_usage}%."
        send_telegram "🚨 High Memory usage detected: *${mem_usage}%*." "CRITICAL"
    fi
    if [ "$disk_usage" -gt "$DISK_CRITICAL_THRESHOLD" ]; then
        log_message "CRITICAL: High Disk usage at ${disk_usage}%."
        send_telegram "🚨 High Disk usage detected: *${disk_usage}%*." "CRITICAL"
    fi
}

# --- Auto-Restart Function ---

attempt_restart_nodeos() {
    if [ "$AUTO_RESTART_NODEOS" != "true" ]; then
        log_message "Auto-restart is disabled. Manual intervention required."
        return 1
    fi

    local count=0
    if [ -f "$RESTART_STATE_FILE" ]; then
        count=$(cat "$RESTART_STATE_FILE")
    fi

    if [ "$count" -ge "$MAX_RESTART_ATTEMPTS" ]; then
        log_message "CRITICAL: Maximum restart attempts ($MAX_RESTART_ATTEMPTS) reached. Auto-restart aborted. Manual intervention required."
        send_telegram "🚨 Maximum restart attempts reached. *Manual intervention required*." "CRITICAL"
        return 1
    fi

    count=$((count + 1))
    echo "$count" > "$RESTART_STATE_FILE"

    log_message "Attempting to restart nodeos (Attempt $count of $MAX_RESTART_ATTEMPTS)..."
    send_telegram "🔄 Attempting to restart nodeos (Attempt *$count*)..." "WARNING"

    (cd "$NODEOS_DIR" && ./stop.sh && sleep 10 && ./start.sh) > /dev/null 2>&1 &
    
    log_message "Restart command issued. Waiting to check status..."
    sleep 45

    if check_nodeos_process; then
        log_message "SUCCESS: Nodeos restarted successfully."
        send_telegram "✅ Nodeos restarted *successfully*." "SUCCESS"
        rm -f "$RESTART_STATE_FILE"
        return 0
    else
        log_message "CRITICAL: Nodeos failed to restart."
        send_telegram "🚨 Nodeos *failed to restart*." "CRITICAL"
        return 1
    fi
}

# --- Main Monitoring Logic ---

run_monitoring() {
    log_message "Starting '$CHECK_TYPE' check..."

    if ! check_nodeos_process; then
        log_message "CRITICAL: nodeos process is not running."
        send_telegram "🚨 CRITICAL: *nodeos process is STOPPED*." "CRITICAL"
        attempt_restart_nodeos
        return
    fi

    if ! check_local_api > /dev/null; then
        log_message "CRITICAL: Local API is not responding."
        send_telegram "🚨 CRITICAL: *Local API is not responding*." "CRITICAL"
        attempt_restart_nodeos
        return
    fi

    if [ -f "$RESTART_STATE_FILE" ]; then
        log_message "System is healthy. Resetting restart attempt counter."
        rm -f "$RESTART_STATE_FILE"
    fi

    if [ "$CHECK_TYPE" == "detailed" ] || [ "$CHECK_TYPE" == "daily" ]; then
        check_sync_status
        check_system_resources
    fi

    log_message "'$CHECK_TYPE' check completed successfully."
    
    # Send a success message unless in silent mode.
    if ! $SILENT_MODE; then
        if [ "$CHECK_TYPE" == "basic" ]; then
            send_telegram "✅ *Health Check: OK*\n\nAll basic systems are running correctly." "SUCCESS"
        else
            send_telegram "✅ *Status Check: OK*\n\nAll systems are nominal." "SUCCESS"
        fi
    fi
}

# --- Daily Report Function ---

generate_daily_report() {
    local nodeos_pid
    if nodeos_pid=$(pgrep -x "nodeos"); then
        local nodeos_status="RUNNING:$nodeos_pid"
    else
        local nodeos_status="STOPPED"
    fi

    local public_api_block=$(check_public_api)
    if [ -n "$public_api_block" ]; then
        local api_status="OK:$public_api_block"
    else
        local api_status="FAILED"
    fi

    local local_block=$(check_local_api)
    local sync_status="N/A"
    if [ -n "$local_block" ] && [ -n "$public_api_block" ]; then
        local diff=$((public_api_block - local_block))
        if [ "$diff" -lt "$MAX_BLOCKS_BEHIND" ]; then
            sync_status="SYNCED:$diff"
        else
            sync_status="BEHIND:$diff"
        fi
    fi

    local resources_cpu=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    local resources_mem=$(free | grep Mem | awk '{printf "%.1f", $3/$2 * 100.0}')
    local resources_disk=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    local resources="CPU:${resources_cpu}% MEM:${resources_mem}% DISK:${resources_disk}%"

    local today=$(date '+%Y-%m-%d')
    local issues_detected=$(grep "$today" "$LOG_FILE" | grep -c -E "CRITICAL|WARNING|ERROR|failed|stopped")
    local uptime_info=$(uptime -p)
    local load_avg=$(uptime | awk -F'load average: ' '{print $2}')

    local report="*📊 Daily Status Report*\n\n"
    report+="*🔧 Current Status:*\n"
    report+=" • Nodeos: \`$nodeos_status\`\n"
    report+=" • Public API: \`$api_status\`\n"
    report+=" • Sync: \`$sync_status\`\n"
    report+=" • Resources: \`$resources\`\n\n"
    report+="*📈 24h Summary:*\n"
    report+=" • Issues Detected: \`$issues_detected\`\n"
    report+=" • Load Average: \`$load_avg\`\n\n"
    report+="*ℹ️ System Info:*\n"
    report+=" • Uptime: \`$uptime_info\`"

    send_telegram "$report" "INFO"
}

# --- Main Execution ---

case "$CHECK_TYPE" in
    "basic"|"detailed")
        run_monitoring
        ;;
    "daily")
        generate_daily_report
        ;;
    "test")
        send_telegram "🧪 This is a test notification from the XPR Monitoring script." "INFO"
        ;;
    *)
        echo "Usage: $0 [--silent] [basic|detailed|daily|test]"
        exit 1
        ;;
esac
