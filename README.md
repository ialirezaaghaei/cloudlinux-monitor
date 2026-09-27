# CloudLinux Monitor

Lightweight CPU, RAM and Disk resource monitoring for CloudLinux + cPanel servers.

CloudLinux Monitor collects resource usage, generates JSON data and static HTML reports, and provides a simple dashboard for identifying accounts with high CPU, RAM or Disk usage.

No database is required.

## Features

- Daily CloudLinux CPU/RAM monitoring
- CPU/RAM normalization against account limits
- Configurable resource threshold
- CPU/RAM fault information
- Daily report with all CloudLinux accounts
- Highlighting of accounts above the configured threshold
- Rolling 15-day CPU/RAM analysis
- Disk quota monitoring through cPanel WHM API
- Static HTML reports
- JSON data
- Web dashboard
- Configurable retention
- No database required
- Automatic Cron installation
- Safe Cron management
- Existing Cron entries are preserved
- Install / Uninstall / Complete Purge support

## Requirements

- CloudLinux
- cPanel / WHM
- AlmaLinux or compatible RHEL-based system
- root access
- Bash
- jq

Expected binaries:

    /usr/sbin/cloudlinux-statistics
    /usr/local/cpanel/bin/whmapi1
    /usr/bin/jq

## Installation

Clone the repository:

    git clone https://github.com/YOUR-ORG/cloudlinux-monitor.git
    cd cloudlinux-monitor

Run the installer as root:

    chmod +x install.sh
    ./install.sh

The installer will:

- Create the configuration file
- Install the monitoring commands
- Install the dashboard
- Create required directories
- Install the CloudLinux Monitor Cron jobs
- Preserve existing root Cron entries
- Avoid duplicate CloudLinux Monitor Cron entries

Configuration is stored at:

    /etc/cloudlinux-monitor.conf

The installer does not overwrite an existing configuration file.

## Configuration

Default configuration:

    BASE="/var/www/html/cloudlinux-monitor"
    THRESHOLD=80
    RETENTION_DAYS=90
    DAYS=15
    LIMIT=1000
    CLOUDLINUX_STATISTICS="/usr/sbin/cloudlinux-statistics"
    WHMAPI="/usr/local/cpanel/bin/whmapi1"
    JQ="/usr/bin/jq"

### Configuration Options

| Option | Description |
|---|---|
| `BASE` | Dashboard, data and report directory |
| `THRESHOLD` | CPU/RAM monitoring threshold |
| `RETENTION_DAYS` | Number of days to retain generated files |
| `DAYS` | Rolling analysis period |
| `LIMIT` | Maximum number of CloudLinux accounts to process |
| `CLOUDLINUX_STATISTICS` | Path to CloudLinux statistics binary |
| `WHMAPI` | Path to cPanel WHM API binary |
| `JQ` | Path to jq |

After changing the configuration, run:

    ./install.sh

The existing configuration is preserved by the installer.

## Dashboard

The dashboard is installed at:

    /var/www/html/cloudlinux-monitor/index.html

After installation, it can be accessed through the web server using the configured `BASE` path.

The dashboard provides links to:

- Daily CPU/RAM Report
- Rolling 15-Day Report
- Disk Report

## Daily CPU/RAM Report

The Daily report uses:

    /usr/sbin/cloudlinux-statistics

and analyzes the last 24 hours.

It includes all CloudLinux accounts returned by CloudLinux Statistics.

For each account, the report displays:

- Username
- Domain
- CPU average
- CPU limit
- CPU usage percentage
- RAM average
- RAM limit
- RAM usage percentage
- Resource status

Accounts reaching or exceeding the configured threshold are highlighted.

The default threshold is:

    80%

## Disk Report

Disk usage is collected from cPanel using:

    /usr/local/cpanel/bin/whmapi1

The Disk report checks account disk quota usage and highlights accounts based on their percentage of allocated disk space.

Default severity levels:

    80%+   Warning
    90%+   Critical
    95%+   Urgent
    100%+  Over Quota

Unlimited disk quotas are excluded from percentage-based analysis.

## Manual Test

After installation, the monitoring commands can be executed manually.

Daily CPU/RAM:

    /usr/local/bin/cloudlinux-monitor-daily

Disk:

    /usr/local/bin/cloudlinux-monitor-disk

15-Day analysis:

    /usr/local/bin/cloudlinux-monitor-15day

Check generated files:

    ls -lh /var/www/html/cloudlinux-monitor/data/

    ls -lh /var/www/html/cloudlinux-monitor/reports/

## Cron

The installer automatically manages the CloudLinux Monitor Cron block.

Default schedule:

    01:00  Daily CloudLinux CPU/RAM
    01:15  Daily Disk
    02:30  Rolling 15-Day analysis

The installer adds the following managed block to the root user's Crontab:

    # BEGIN CLOUDLINUX-MONITOR
    0 1 * * * /usr/local/bin/cloudlinux-monitor-daily >> /var/log/cloudlinux-daily.log 2>&1
    15 1 * * * /usr/local/bin/cloudlinux-monitor-disk >> /var/log/cpanel-disk.log 2>&1
    30 2 * * * /usr/local/bin/cloudlinux-monitor-15day >> /var/log/cloudlinux-15day.log 2>&1
    # END CLOUDLINUX-MONITOR

Existing Crontab entries are preserved.

The installer is idempotent, so running `./install.sh` multiple times will not create duplicate CloudLinux Monitor Cron blocks.

Check the installed Cron block:

    crontab -l | sed -n '/# BEGIN CLOUDLINUX-MONITOR/,/# END CLOUDLINUX-MONITOR/p'

## Logs

The monitoring jobs write to:

    /var/log/cloudlinux-daily.log
    /var/log/cpanel-disk.log
    /var/log/cloudlinux-15day.log

## Output

The default output directory is:

    /var/www/html/cloudlinux-monitor/
    ├── index.html
    ├── data/
    │   ├── YYYY-MM-DD.json
    │   ├── 15day-YYYY-MM-DD.json
    │   └── disk-YYYY-MM-DD.json
    └── reports/
        ├── report-YYYY-MM-DD.html
        ├── report-15day-YYYY-MM-DD.html
        └── report-disk-YYYY-MM-DD.html

Runtime JSON and HTML files should not be committed to Git.

## CPU Normalization

CloudLinux CPU usage is normalized against the account CPU limit:

    CPU % = CPU average / CPU limit × 100

For example:

    CPU average = 50
    CPU limit   = 100

    CPU usage = 50%

CloudLinux CPU values should not be multiplied by 100 again before normalization.

## RAM Normalization

CloudLinux PMEM values are reported in bytes and are converted to MB for reporting.

    RAM % = RAM average / RAM limit × 100

For example:

    RAM average = 512 MB
    RAM limit   = 1024 MB

    RAM usage = 50%

## 15-Day Status Logic

The rolling 15-day report analyzes available daily CPU/RAM data.

### Upgrade Candidate

Average CPU or RAM is at least the configured threshold.

### Review

CPU or RAM reaches the threshold on at least 5 days, while the average remains below the threshold.

### Watch

CPU or RAM reaches the threshold on at least 1 day, but usage is not persistent.

### Normal

No available day reaches the configured threshold.

Faults are displayed as additional investigation signals and do not independently trigger an upgrade status.

## Data Availability

The 15-day report requires daily data.

On a newly installed server, fewer than 15 days may be available.

The report indicates the number of available days, for example:

    Data available: 1/15 days

As daily reports accumulate, the rolling analysis will progressively cover the full configured period.

## Retention

Generated JSON and HTML files are automatically removed after the configured retention period.

The default retention period is:

    90 days

Configure it using:

    RETENTION_DAYS=90

## Uninstallation

To remove the application while preserving collected data and reports:

    ./uninstall.sh

The normal uninstall removes:

- CloudLinux Monitor Cron block
- Installed monitoring commands
- Configuration file
- Dashboard

The following are preserved:

    data/
    reports/

Existing unrelated Cron entries are preserved.

## Complete Removal

To remove the application and all collected data:

    ./uninstall.sh --purge-data

This removes:

- CloudLinux Monitor Cron block
- Monitoring commands
- Configuration
- Dashboard
- JSON data
- HTML reports
- CloudLinux Monitor directory

The operation requires confirmation.

This operation is destructive and should only be used when the collected data is no longer required.

## Updating

On an installed server:

    cd /path/to/cloudlinux-monitor
    git pull
    ./install.sh

The existing configuration:

    /etc/cloudlinux-monitor.conf

is preserved.

The installer safely updates the installed monitoring scripts, dashboard and Cron configuration.

## Privacy

Do not commit real customer data to Git.

Before pushing changes:

    git status

Make sure real:

- domains
- usernames
- JSON files
- HTML reports
- server-specific data

are not staged.

Runtime data and reports should remain outside the Git repository.

## Security Considerations

The dashboard contains hosting account information such as usernames, domains and resource usage.

If the dashboard is exposed through a public web server, access control should be considered.

Recommended options include:

- HTTP Basic Authentication
- IP-based access restriction
- Private/internal network access
- Web server authentication or SSO

Do not expose customer resource information publicly unless this is intentional.

## Repository Structure

    cloudlinux-monitor/
    ├── README.md
    ├── LICENSE
    ├── .gitignore
    ├── install.sh
    ├── uninstall.sh
    ├── config/
    │   └── monitor.conf.example
    ├── scripts/
    │   ├── cloudlinux-daily.sh
    │   ├── cloudlinux-15day.sh
    │   └── cpanel-disk.sh
    ├── cron/
    │   └── cloudlinux-monitor.cron
    ├── web/
    │   └── index.html
    ├── data/
    │   └── .gitkeep
    └── reports/
        └── .gitkeep

## License

MIT
