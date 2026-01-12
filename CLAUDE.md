# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

Azure Cost Monitor is a local monitoring solution for Azure Sponsorship subscriptions. It tracks costs, detects unexpected Marketplace charges, and provides a dashboard for visualizing usage.

**Key Insight**: Azure Sponsorship does NOT cover Azure Marketplace/SaaS purchases (like Anthropic Claude via AI Foundry).

## Project Structure

```
azure-monitor/
├── README.md                 # Full documentation
├── check-usage.sh           # CLI usage report (legacy)
├── reports/                 # Daily CLI reports
└── dashboard/
    ├── collect-data.sh      # Main data collection (hourly)
    ├── start.sh             # Dashboard launcher
    ├── index.html           # Dashboard UI (Chart.js)
    ├── data.json            # Current data
    └── history.json         # Historical snapshots
```

## Common Commands

```bash
# Start dashboard
cd dashboard && python3 -m http.server 8847
# Or
./dashboard/start.sh

# Manual data collection
./dashboard/collect-data.sh

# Check scheduler
launchctl list | grep azure

# View logs
tail -f dashboard/collect.log

# Restart scheduler
launchctl unload ~/Library/LaunchAgents/com.azure.usage-monitor.plist
launchctl load ~/Library/LaunchAgents/com.azure.usage-monitor.plist
```

## Key Files

### `dashboard/collect-data.sh`

Bash script that:
1. Fetches token metrics from Azure Monitor for all OpenAI accounts
2. Calculates cost estimates using model-specific pricing
3. Fetches invoices from Azure Billing API
4. Outputs `data.json` for the dashboard

**Important**: Uses case statements for pricing (not bash associative arrays) for macOS compatibility.

### `dashboard/index.html`

Single-page dashboard with:
- Sponsorship countdown banner
- Chart.js graphs (token usage, cost by account)
- Invoice history table
- Auto-refresh every hour

### `~/Library/LaunchAgents/com.azure.usage-monitor.plist`

macOS scheduler running `collect-data.sh` hourly.

## Azure Resources

### Covered by Sponsorship (kind: OpenAI)
- myazurellm
- careerfied-openai
- qlaunch-openai-*
- brandtruth-dalle

### Monitor for Claude (kind: AIServices)
- skyller-dev-resource
- qnews-resource
- satis-mggd0m1a-eastus2

### Deleted (were billing Marketplace)
- quantumlayer-rf-resource
- qlp-scout-resource
- satis-mhyhfjhv-swedencentral

## Alert Configuration

Activity Log Alerts in `qlp-rg` resource group:
- `NewResourceCreated` - Any deployment
- `AIServicesCreated` - AI/Cognitive Services
- `MarketplaceSaaSCreated` - SaaS subscriptions

Action Group: `SpendingAlerts` → satishgs@outlook.com

## Pricing Reference

```bash
# Per 1K tokens (USD)
get_input_price() {
    case "$1" in
        gpt-4) echo "0.03" ;;
        gpt-4o*) echo "0.005" ;;
        gpt-4.1) echo "0.002" ;;
        gpt-4.1-mini) echo "0.0004" ;;
        gpt-5) echo "0.01" ;;
        *) echo "0.01" ;;
    esac
}
```

## Troubleshooting

### Script fails with "declare -A invalid"
macOS default bash (3.x) doesn't support associative arrays. Use case statements instead.

### Invoices not showing
Check billing account ID: `86977968-84de-43a3-be1f-ba01891b28ef`

### Dashboard not loading data
Run `./dashboard/collect-data.sh` manually and check for errors.

### Scheduler not running
```bash
launchctl list | grep azure
# If not listed, reload:
launchctl load ~/Library/LaunchAgents/com.azure.usage-monitor.plist
```

## Related Projects

Projects updated to use Azure OpenAI instead of Claude:
- `/Users/satish/qlp-projects/ql-rf` - Changed to azure_openai provider
- `/Users/satish/qlp-projects/QLP-Scout` - Already using azure_openai
