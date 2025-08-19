#!/bin/bash

# ==============================================================================
# XPR Network Telegram Bot - Interactive Command Handler
#
# Description: Listens for commands via Telegram and executes corresponding
#              actions from the monitoring script. Uses long polling.
# Author:      Artwebin Team
# Version:     2.0
# ==============================================================================

# --- Configuration and Initialization ---
set -o pipefail
CONFIG_FILE="/etc/xpr-monitor/config.conf"
LOG_FILE="/var/log/xpr-monitor.log"
MONITOR_SCRIPT="/usr/local/bin/xpr_monitor.sh"

# --- Load Configuration ---
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "CRITICAL: Bot could not start. Configuration file not found at $CONFIG_FILE."
    exit 1
fi

# --- Check if Bot is Enabled ---
if [ "$ENABLE_TELEGRAM_BOT" != "true" ]; then
    echo "INFO: Telegram bot is disabled in the configuration. Exiting."
    exit 0
fi

# --- Default values (if not set in config) ---
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-"YOUR_TOKEN_HERE"}"
CHAT_ID="${CHAT_ID:-"YOUR_CHAT_ID_HERE"}"
BP_NAME="${BP_NAME:-"MyXPRNode"}"
API_URL="https://api.telegram.org/bot$TELEGRAM_TOKEN"

# --- Helper Functions ---

log_message( ) {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [BOT] - $1" >> "$LOG_FILE"
}

send_message() {
    local chat_id_to_send="$1"
    local message="$2"
    local formatted_message=$(echo -e "$message")
    
    # Prepend the header to the main message
    local full_message_with_header="🖥️ *$BP_NAME Monitor*\n\n$formatted_message"

    curl -s -X POST "$API_URL/sendMessage" \
        -d "chat_id=$chat_id_to_send" \
        -d "text=$full_message_with_header" \
        -d "parse_mode=Markdown" > /dev/null
}

# --- Main Command Processing Logic ---

process_command() {
    local message_text="$1"
    local chat_id="$2"
    local command args

    read -r command args <<< "$message_text"

    log_message "Received command '$command' with args '$args' from chat ID $chat_id"

    if [ "$chat_id" != "$CHAT_ID" ]; then
        log_message "Unauthorized access attempt from chat ID $chat_id. Ignoring."
        send_message "$chat_id" "⛔️ *Access Denied*\n\nYou are not authorized to use this bot."
        return
    fi

    case "$command" in
        "/status"|"/start")
            send_message "$chat_id" "⏳ *Running Full Status Check...*\n\nThis may take a moment. The report will be sent by the monitor script."
            "$MONITOR_SCRIPT" detailed
            ;;
        "/health")
            # The monitor script will send its own success/failure message
            "$MONITOR_SCRIPT" basic
            ;;
        "/report")
            send_message "$chat_id" "⏳ *Generating Daily Report...*"
            "$MONITOR_SCRIPT" daily
            ;;
        "/logs")
            local log_lines=15
            local search_term="${args:-"all"}"
            local log_output

            if [ "$search_term" == "all" ]; then
                log_output=$(tail -n "$log_lines" "$LOG_FILE")
                send_message "$chat_id" "📋 *Last $log_lines Log Entries:*\n\n\`\`\`\n$log_output\n\`\`\`"
            else
                log_output=$(grep -i "$search_term" "$LOG_FILE" | tail -n "$log_lines")
                if [ -n "$log_output" ]; then
                    send_message "$chat_id" "📋 *Last $log_lines Log Entries matching '$search_term':*\n\n\`\`\`\n$log_output\n\`\`\`"
                else
                    send_message "$chat_id" "ℹ️ No log entries found matching '*$search_term*'."
                fi
            fi
            ;;
        "/restart_info")
            send_message "$chat_id" "🔄 *Restart Info*\n\nAutomatic restart via bot is disabled for security.\nTo restart the node, connect to the server and run:\n\`sudo systemctl restart nodeos\`"
            ;;
        "/help")
            local help_text="🤖 *XPR Monitor Bot Commands*\n\n"
            help_text+="*/status* - Runs a full, detailed system status check.\n"
            help_text+="*/health* - Runs a quick, basic health check.\n"
            help_text+="*/report* - Generates and sends the daily summary report.\n"
            help_text+="*/logs [keyword]* - Shows the last 15 log entries. Optionally, you can filter by a keyword (e.g., \`/logs error\`).\n"
            help_text+="*/restart_info* - Shows instructions for manually restarting the node.\n"
            help_text+="*/help* - Shows this help message."
            send_message "$chat_id" "$help_text"
            ;;
        *)
            send_message "$chat_id" "❓ *Unknown Command*\n\nI don't recognize the command '$command'. Use /help to see available options."
            ;;
    esac
}

# --- Main Loop for Long Polling ---

log_message "Telegram bot service started. Listening for commands..."
offset=0
while true; do
    updates=$(curl -s --max-time 70 "$API_URL/getUpdates?offset=$offset&limit=10&timeout=60")
    
    if [ -n "$updates" ] && [ "$(echo "$updates" | jq -r '.ok')" = "true" ]; then
        # Correct way to process JSON array in a loop without a subshell
        while IFS= read -r message_obj; do
            if [ -z "$message_obj" ]; then continue; fi
            
            update_id=$(echo "$message_obj" | jq '.update_id')
            message_text=$(echo "$message_obj" | jq -r '.message.text // .edited_message.text // ""')
            chat_id=$(echo "$message_obj" | jq -r '.message.chat.id // .edited_message.chat.id // ""')

            if [ -n "$message_text" ] && [ -n "$chat_id" ]; then
                process_command "$message_text" "$chat_id"
            fi
            
            # Update offset to the next update_id to avoid processing the same message again
            offset=$((update_id + 1))
        done < <(echo "$updates" | jq -c '.result[]')
    fi
    sleep 1
done
