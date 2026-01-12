# Azure Cost Monitor

A comprehensive Azure cost monitoring and alerting solution for tracking spending, detecting billing issues, and visualizing usage across Azure Sponsorship subscriptions.

**Created:** January 9, 2026
**Purpose:** Monitor Azure costs, detect unexpected Marketplace charges, track sponsorship usage

## Background

This project was created after discovering an unexpected £1,099.30 invoice from Anthropic (Claude API) accessed via Azure AI Foundry. The key finding was:

- **Azure Sponsorship credits do NOT cover Azure Marketplace/SaaS purchases**
- Claude models accessed through Azure AI Foundry are billed as third-party Marketplace SaaS
- Azure-native services (OpenAI, Storage, Compute) ARE covered by sponsorship

### Problem Solved

| Issue | Solution |
|-------|----------|
| Unexpected Marketplace billing | Real-time alerts on SaaS/AI resource creation |
| No visibility into costs | Dashboard with usage metrics and cost estimates |
| Unknown sponsorship timeline | Countdown to April 2026 expiry with projections |
| Invoice tracking | Automated invoice fetching from Azure Billing API |

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AZURE SUBSCRIPTION                                 │
│                     (Microsoft Azure Sponsorship)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │  OpenAI Service  │  │   AI Services    │  │  Marketplace     │          │
│  │  (Covered)       │  │  (Monitor)       │  │  SaaS (NOT       │          │
│  │                  │  │                  │  │  Covered)        │          │
│  │  - myazurellm    │  │  - skyller-dev   │  │  - Anthropic     │          │
│  │  - careerfied    │  │  - qnews         │  │    (DELETED)     │          │
│  │  - qlaunch       │  │  - satis-*       │  │                  │          │
│  └────────┬─────────┘  └────────┬─────────┘  └──────────────────┘          │
│           │                     │                                           │
│           ▼                     ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────┐       │
│  │                    Azure Monitor Metrics                         │       │
│  │  - ProcessedPromptTokens                                         │       │
│  │  - GeneratedCompletionTokens                                     │       │
│  │  - Activity Logs                                                 │       │
│  └─────────────────────────────────────────────────────────────────┘       │
│                                    │                                        │
└────────────────────────────────────┼────────────────────────────────────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
                    ▼                ▼                ▼
┌───────────────────────┐  ┌─────────────────┐  ┌─────────────────────────┐
│   Activity Log        │  │  Azure Billing  │  │   collect-data.sh       │
│   Alerts              │  │  API            │  │   (Hourly via           │
│                       │  │                 │  │    LaunchAgent)         │
│  - NewResourceCreated │  │  - Invoices     │  │                         │
│  - AIServicesCreated  │  │  - Amounts      │  │  - Token metrics        │
│  - MarketplaceSaaS    │  │  - Status       │  │  - Cost estimates       │
│                       │  │                 │  │  - Resource counts      │
└───────────┬───────────┘  └────────┬────────┘  └────────────┬────────────┘
            │                       │                        │
            ▼                       │                        ▼
┌───────────────────────┐           │           ┌─────────────────────────┐
│   Action Group        │           │           │     data.json           │
│   (SpendingAlerts)    │           │           │                         │
│                       │           │           │  - Token usage (30d)    │
│   Email:              │           │           │  - Cost breakdown       │
│   satishgs@outlook.com│           │           │  - Sponsorship status   │
└───────────────────────┘           │           │  - Invoice history      │
                                    │           │  - Daily metrics        │
                                    │           └────────────┬────────────┘
                                    │                        │
                                    │                        ▼
                                    │           ┌─────────────────────────┐
                                    └──────────►│   Dashboard (HTML)      │
                                                │   Port 8847             │
                                                │                         │
                                                │  - Sponsorship banner   │
                                                │  - Usage charts         │
                                                │  - Cost projections     │
                                                │  - Invoice history      │
                                                │  - Auto-refresh (1hr)   │
                                                └─────────────────────────┘
```

## Components

### 1. Data Collection (`dashboard/collect-data.sh`)

Bash script that collects Azure usage data via Azure CLI:

- **Token Metrics**: Fetches ProcessedPromptTokens and GeneratedCompletionTokens for all OpenAI accounts
- **Cost Estimation**: Calculates costs using model-specific pricing (GPT-4, GPT-4.1, GPT-5, etc.)
- **Resource Inventory**: Counts Storage, PostgreSQL, Container Apps
- **Invoice Fetching**: Pulls invoice data from Azure Billing API
- **Sponsorship Tracking**: Calculates days remaining until April 2026

**Schedule**: Runs hourly via macOS LaunchAgent

### 2. Dashboard (`dashboard/index.html`)

Single-page web dashboard with:

| Section | Description |
|---------|-------------|
| Sponsorship Banner | Days remaining, monthly cost offset, projected cost to April |
| Summary Cards | Total tokens, costs, daily trends, alerts |
| Usage Charts | 7-day token/cost graph, cost by account donut chart |
| Account Table | Per-account breakdown with model, tokens, estimated cost |
| AI Services Monitor | Lists AIServices resources that could host Claude |
| Cost Projection | Breakdown by service type (OpenAI, Storage, DB, Apps) |
| Invoice History | All Marketplace invoices with status, amounts, totals |

**Auto-refresh**: Every hour (client-side JavaScript)

### 3. Activity Log Alerts

Real-time email notifications for:

| Alert | Trigger |
|-------|---------|
| `NewResourceCreated` | Any new Azure deployment |
| `AIServicesCreated` | New AI/Cognitive Services account |
| `MarketplaceSaaSCreated` | New Marketplace SaaS subscription |

**Action Group**: SpendingAlerts → satishgs@outlook.com

### 4. Scheduler (`com.azure.usage-monitor.plist`)

macOS LaunchAgent configuration:

- **Frequency**: Every 3600 seconds (1 hour)
- **RunAtLoad**: Yes (runs immediately on login)
- **Logs**: `dashboard/collect.log`

## Project Structure

```
azure-monitor/
├── README.md                 # This documentation
├── check-usage.sh           # Legacy CLI usage report script
├── reports/                 # Daily CLI report files
│   └── usage-YYYY-MM-DD.txt
│
└── dashboard/
    ├── collect-data.sh      # Main data collection script
    ├── start.sh             # One-click dashboard launcher
    ├── index.html           # Dashboard UI
    ├── data.json            # Current data (auto-generated)
    ├── history.json         # Historical snapshots
    ├── collect.log          # Scheduler output log
    └── com.azure.usage-monitor.plist  # LaunchAgent template
```

## Pricing Model

Costs are estimated based on Azure OpenAI public pricing (USD per 1K tokens):

| Model | Input | Output |
|-------|-------|--------|
| GPT-4 | $0.030 | $0.060 |
| GPT-4o | $0.005 | $0.015 |
| GPT-4.1 | $0.002 | $0.008 |
| GPT-4.1-mini | $0.0004 | $0.0016 |
| GPT-4.1-nano | $0.0001 | $0.0004 |
| GPT-5 | $0.010 | $0.030 |
| GPT-5-pro | $0.020 | $0.060 |
| o4-mini | $0.003 | $0.012 |
| text-embedding-3-small | $0.00002 | - |

## Quick Start

### View Dashboard

```bash
# Start dashboard server
cd /Users/satish/qlp-projects/azure-monitor/dashboard
python3 -m http.server 8847

# Open in browser
open http://localhost:8847
```

Or use the one-liner:

```bash
/Users/satish/qlp-projects/azure-monitor/dashboard/start.sh
```

### Manual Data Refresh

```bash
/Users/satish/qlp-projects/azure-monitor/dashboard/collect-data.sh
```

### Check Scheduler

```bash
# Status
launchctl list | grep azure

# Logs
tail -f /Users/satish/qlp-projects/azure-monitor/dashboard/collect.log

# Restart
launchctl unload ~/Library/LaunchAgents/com.azure.usage-monitor.plist
launchctl load ~/Library/LaunchAgents/com.azure.usage-monitor.plist
```

## Invoice Summary

### Marketplace Invoices (Anthropic/Claude - NOT Covered)

| Invoice | Period | Amount | Status |
|---------|--------|--------|--------|
| G128680165 | Nov 2025 | £164.17 | ✓ Paid |
| G134475527 | Dec 2025 | £1,099.30 | Due |
| (Pending) | Jan 1-9, 2026 | ~£330 | Projected |

**Total Marketplace Charges**: ~£1,593

### Actions Taken (Jan 9, 2026)

1. **Deleted Claude Resources**:
   - `quantumlayer-rf-resource` (ql-rf project)
   - `qlp-scout-resource` (QLP-Scout project)
   - `satis-mhyhfjhv-swedencentral` (Claude opus/sonnet/haiku)

2. **Updated Project Configs**:
   - `ql-rf/.env`: Changed from `azure_anthropic` to `azure_openai` (myazurellm)
   - QLP-Scout: Already using Azure OpenAI

3. **Set Up Monitoring**:
   - Activity Log Alerts for resource creation
   - Hourly data collection
   - Dashboard with invoice tracking

## Sponsorship Details

| Property | Value |
|----------|-------|
| Subscription | Microsoft Azure Sponsorship |
| Subscription ID | C6BE500C-48E8-4975-B2F3-7AF12C9B751D |
| Offer Type | MS-AZR-0036P |
| Ends | April 30, 2026 |
| Covers | Azure-native services (OpenAI, Compute, Storage, etc.) |
| Does NOT Cover | Marketplace SaaS (Anthropic, third-party services) |

## Key Learnings

1. **Azure AI Foundry ≠ Azure OpenAI**: AI Foundry can host third-party models (Claude) billed as Marketplace SaaS
2. **Check `kind` field**: `OpenAI` = covered, `AIServices` = may have Marketplace models
3. **Cost Management limitations**: Standard budget alerts don't work for Sponsorship subscriptions
4. **Activity Log Alerts**: Alternative monitoring approach for unsupported subscription types

## Environment Variables

The data collection script uses Azure CLI with logged-in credentials:

```bash
# Verify Azure login
az account show

# Billing account (for invoice access)
BILLING_ACCOUNT="86977968-84de-43a3-be1f-ba01891b28ef"
```

## Dependencies

- **Azure CLI** (`az`) - For all Azure API calls
- **jq** - JSON processing
- **bc** - Cost calculations
- **Python 3** - Dashboard web server
- **macOS LaunchAgent** - Scheduler (or cron on Linux)

## Port Selection

**Dashboard Port: 8847**

Chosen to avoid conflicts with common development ports:
- 3000 (Next.js, React)
- 8000 (Python)
- 8080 (Java, Go)
- 8090 (Various)
- 9000 (PHP, MinIO)
