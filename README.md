# XPR Network Node Monitoring Suite

A comprehensive, lightweight, and easy-to-install monitoring suite for XPR Network Block Producers and node operators. This suite provides automated health checks, system resource monitoring, and instant notifications via a fully interactive Telegram bot.



## Features

- ✅ **Automated Health Checks**: Monitors the `nodeos` process, local API, and public API endpoints.
- ⚙️ **System Resource Monitoring**: Tracks CPU, RAM, and disk usage, sending alerts on critical thresholds.
- 🔄 **Auto-Restart**: Intelligently attempts to restart the `nodeos` process if it stops responding, with a configurable attempt limit to prevent loops.
- 🔔 **Telegram Notifications**: Get instant alerts for critical issues and daily status reports.
- 🤖 **Interactive Telegram Bot**: Use simple commands to check status, view logs, and get reports on demand.
- 🔧 **Easy Installation**: A single, interactive setup script handles all dependencies, configuration, and service setup.
- 🛡️ **Robust & Modern**: Uses `systemd` for reliable, managed services and timers instead of legacy cron.
- 🪵 **Log Rotation**: Automatically manages and rotates log files to prevent disk space issues.

## Installation

Installation is designed to be as simple as possible. You only need to run one command.

**Prerequisites:**
- A server running a Debian-based OS (like Ubuntu 22.04).
- An XPR Network node already installed.
- A Telegram Bot Token and your Chat ID.

**Steps:**

1.  Clone this repository or download the files to your server.
    ```bash
    git clone https://github.com/artwebin/xpr-node-monitor.git
    cd xpr-node-monitor
    ```

2.  Make the setup script executable:
    ```bash
    chmod +x setup_monitoring.sh
    ```

3.  Run the interactive setup script as root:
    ```bash
    sudo ./setup_monitoring.sh
    ```
    The script will guide you, asking for your Telegram Token and Chat ID, and will handle the rest automatically.

## Configuration

All settings are located in a single, well-documented configuration file:
`/etc/xpr-monitor/config.conf`

You can edit this file to change thresholds, paths, and other advanced settings after installation.
```bash
sudo nano /etc/xpr-monitor/config.conf
```


## Usage
Once installed, the monitoring system runs automatically in the background. You can interact with it via the Telegram bot.

## Telegram Bot Commands
- /status - Runs a full, detailed system status check.
- /health - Runs a quick, basic health check.
- /report - Generates and sends the daily summary report on demand.
- /logs [keyword] - Shows the last 15 log entries. You can optionally filter by a keyword (e.g., /logs error ).
- /restart_info - Shows instructions for manually restarting the node.
- /help - Shows the help message with all available commands.


## Troubleshooting

- Check the main log file:
```Bash
tail -f /var/log/xpr-monitor.log
```

- Check the status of the monitoring timers:
```Bash
systemctl list-timers | grep xpr
```

- Check the status of the Telegram bot service:
```Bash
systemctl status xpr-telegram-bot.service
```



## Uninstallation
To completely remove the monitoring suite from your system, you can run the following commands:

```Bash
# Stop and disable all related systemd services and timers
sudo systemctl stop xpr-monitor-basic.timer xpr-monitor-detailed.timer xpr-monitor-daily.timer xpr-telegram-bot.service
sudo systemctl disable xpr-monitor-basic.timer xpr-monitor-detailed.timer xpr-monitor-daily.timer xpr-telegram-bot.service

# Remove all installed files
sudo rm /usr/local/bin/xpr_monitor.sh
sudo rm /usr/local/bin/telegram_bot.sh
sudo rm -rf /etc/xpr-monitor
sudo rm /var/log/xpr-monitor.log
sudo rm /etc/logrotate.d/xpr-monitor
sudo rm /etc/systemd/system/xpr-monitor-*.service
sudo rm /etc/systemd/system/xpr-monitor-*.timer
sudo rm /etc/systemd/system/xpr-telegram-bot.service

# Reload systemd to apply changes
sudo systemctl daemon-reload
```

## License

This project is licensed under the MIT License. See the LICENSE file for details.
