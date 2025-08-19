#!/bin/bash

# ==============================================================================
# XPR Network Monitoring - Interactive Setup Script
#
# Description: Installs and configures the complete monitoring system,
#              including scripts, dependencies, and systemd services.
# Author:      Artwebin Team
# Version:     2.0
# ==============================================================================

set -e # Exit immediately if a command exits with a non-zero status.

# --- Helper Functions for Colors and Output ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'

info() {
    echo -e "${C_BLUE}INFO:${C_RESET} $1"
}

success() {
    echo -e "${C_GREEN}SUCCESS:${C_RESET} $1"
}

warn() {
    echo -e "${C_YELLOW}WARNING:${C_RESET} $1"
}

error() {
    echo -e "${C_RED}ERROR:${C_RESET} $1" >&2
    exit 1
}

# --- Pre-flight Checks ---
info "Starting XPR Network Monitoring Setup..."

# 1. Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "This script must be run as root. Please use 'sudo ./setup_monitoring.sh'."
fi

# 2. Check for required local files
info "Checking for required script files..."
for file in xpr_monitor.sh telegram_bot.sh xpr-monitor-config.conf; do
    if [ ! -f "$file" ]; then
        error "Required file '$file' not found in the current directory."
    fi
done
success "All required files are present."

# --- Installation Steps ---

# 1. Install Dependencies
info "Updating package list and installing dependencies (curl, jq, bc)..."
apt-get update > /dev/null
apt-get install -y curl jq bc > /dev/null
success "Dependencies installed."

# 2. Create Directories
info "Creating system directories..."
mkdir -p /etc/xpr-monitor
mkdir -p /var/log
mkdir -p /usr/local/bin
success "Directories created."

# 3. Copy Scripts and Set Permissions
info "Copying scripts to /usr/local/bin/ and setting permissions..."
cp xpr_monitor.sh /usr/local/bin/
cp telegram_bot.sh /usr/local/bin/
chmod +x /usr/local/bin/xpr_monitor.sh
chmod +x /usr/local/bin/telegram_bot.sh
success "Scripts installed."

# 4. Interactive Configuration Setup
info "Setting up configuration file..."
if [ -f "/etc/xpr-monitor/config.conf" ]; then
    warn "Existing configuration file found. Skipping interactive setup."
    warn "If you want to re-configure, please remove the old file first:"
    warn "sudo rm /etc/xpr-monitor/config.conf"
else
    cp xpr-monitor-config.conf /etc/xpr-monitor/config.conf

    read -p "Please enter your Telegram Bot Token: " telegram_token
    read -p "Please enter your Telegram Chat ID: " chat_id

    # Use sed to replace placeholder values in the config file
    sed -i "s/TELEGRAM_TOKEN=\".*\"/TELEGRAM_TOKEN=\"$telegram_token\"/" /etc/xpr-monitor/config.conf
    sed -i "s/CHAT_ID=\".*\"/CHAT_ID=\"$chat_id\"/" /etc/xpr-monitor/config.conf
    
    success "Configuration file created and populated with your data."
fi
chmod 600 /etc/xpr-monitor/config.conf
success "Configuration file permissions set to 600."

# 5. Setup Logging
info "Setting up log file and log rotation..."
touch /var/log/xpr-monitor.log
chmod 644 /var/log/xpr-monitor.log

cat > /etc/logrotate.d/xpr-monitor << 'EOF'
/var/log/xpr-monitor.log {
    daily
    rotate 30
    size 20M
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
success "Log file and rotation configured."

# 6. Setup systemd Services and Timers
info "Setting up systemd services and timers..."

# --- Service and Timer for the main monitor script ---
cat > /etc/systemd/system/xpr-monitor-basic.service << 'EOF'
[Unit]
Description=XPR Monitor - Basic Check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/xpr_monitor.sh --silent basic
EOF

cat > /etc/systemd/system/xpr-monitor-basic.timer << 'EOF'
[Unit]
Description=Run XPR basic check every minute
[Timer]
OnCalendar=*:0/1
Persistent=true
[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/xpr-monitor-detailed.service << 'EOF'
[Unit]
Description=XPR Monitor - Detailed Check
[Service]
Type=oneshot
ExecStart=/usr/local/bin/xpr_monitor.sh --silent detailed
EOF

cat > /etc/systemd/system/xpr-monitor-detailed.timer << 'EOF'
[Unit]
Description=Run XPR detailed check every 5 minutes
[Timer]
OnCalendar=*:0/5
Persistent=true
[Install]
WantedBy=timers.target
EOF

cat > /etc/systemd/system/xpr-monitor-daily.service << 'EOF'
[Unit]
Description=XPR Monitor - Daily Report
[Service]
Type=oneshot
ExecStart=/usr/local/bin/xpr_monitor.sh daily
EOF

cat > /etc/systemd/system/xpr-monitor-daily.timer << 'EOF'
[Unit]
Description=Run XPR daily report at 9:00 AM
[Timer]
OnCalendar=*-*-* 09:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

# --- Service for the Telegram Bot (to run continuously) ---
cat > /etc/systemd/system/xpr-telegram-bot.service << 'EOF'
[Unit]
Description=XPR Monitor - Telegram Bot Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/telegram_bot.sh
User=root
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

success "systemd files created."

# 7. Enable and Start Services
info "Reloading systemd, enabling and starting services..."
systemctl daemon-reload

# Enable and start timers for monitoring
systemctl enable --now xpr-monitor-basic.timer
systemctl enable --now xpr-monitor-detailed.timer
systemctl enable --now xpr-monitor-daily.timer

# Enable and start the Telegram bot service
systemctl enable --now xpr-telegram-bot.service

success "All services and timers have been enabled and started."

# --- Final Steps ---
echo
echo -e "${C_GREEN}====================================================="
echo -e "      XPR Network Monitoring Setup Complete!       "
echo -e "=====================================================${C_RESET}"
echo
info "The system is now live. Here's a summary:"
echo "  - Monitoring scripts are running automatically via systemd timers."
echo "  - The interactive Telegram bot is running as a background service."
echo "  - Configuration is located at: /etc/xpr-monitor/config.conf"
echo "  - Logs are written to: /var/log/xpr-monitor.log"
echo
info "You can check the status of the services with:"
echo "  - 'systemctl status xpr-monitor-detailed.timer'"
echo "  - 'systemctl status xpr-telegram-bot.service'"
echo
info "Try sending a '/help' command to your bot on Telegram to test it."
echo
