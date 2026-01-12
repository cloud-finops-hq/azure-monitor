# GitHub Actions + GitHub Pages Setup

## Overview

This setup moves the Azure Cost Monitor from your local Mac to GitHub, making it:
- Always-on (runs every hour, even when Mac is off)
- Accessible anywhere via GitHub Pages URL
- Completely free (no cost)
- Automatic data backup via Git history

## Setup Steps

### 1. Add Azure Credentials to GitHub Secrets

1. Go to your GitHub repository: https://github.com/satishgonella2024/cloud-finops
2. Click **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `AZURE_CREDENTIALS`
5. Value: Copy and paste this entire JSON (already created for you):

```json
{
  "clientId": "YOUR_SERVICE_PRINCIPAL_CLIENT_ID",
  "clientSecret": "YOUR_SERVICE_PRINCIPAL_SECRET",
  "subscriptionId": "YOUR_AZURE_SUBSCRIPTION_ID",
  "tenantId": "YOUR_AZURE_TENANT_ID",
  "activeDirectoryEndpointUrl": "https://login.microsoftonline.com",
  "resourceManagerEndpointUrl": "https://management.azure.com/",
  "activeDirectoryGraphResourceId": "https://graph.windows.net/",
  "sqlManagementEndpointUrl": "https://management.core.windows.net:8443/",
  "galleryEndpointUrl": "https://gallery.azure.com/",
  "managementEndpointUrl": "https://management.core.windows.net/"
}
```

**Note:** Use the service principal credentials created by running:
```bash
az ad sp create-for-rbac --name "github-actions-azure-monitor" --role reader --scopes /subscriptions/YOUR_SUBSCRIPTION_ID --sdk-auth
```

6. Click **Add secret**

### 2. Enable GitHub Pages

1. In your repository, go to **Settings** → **Pages**
2. Under **Source**, select **Deploy from a branch**
3. Under **Branch**, select **main** and folder **/ (root)**
4. Click **Save**

Your dashboard will be available at: **https://satishgonella2024.github.io/cloud-finops/dashboard/**

### 3. Push the Workflow

The workflow file has been created at `.github/workflows/collect-azure-data.yml`. Commit and push it:

```bash
git add .github/workflows/collect-azure-data.yml GITHUB_ACTIONS_SETUP.md
git commit -m "Add GitHub Actions workflow for automated data collection"
git push
```

### 4. Test the Workflow

1. Go to **Actions** tab in your GitHub repository
2. Click on **Collect Azure Cost Data** workflow
3. Click **Run workflow** → **Run workflow** (manual trigger)
4. Wait for it to complete (~1-2 minutes)
5. Check if `dashboard/data.json` was updated

### 5. Disable Local Scheduler (Optional)

Once GitHub Actions is working, you can disable the local Mac scheduler:

```bash
launchctl unload ~/Library/LaunchAgents/com.azure.usage-monitor.plist
```

To re-enable it later:
```bash
launchctl load ~/Library/LaunchAgents/com.azure.usage-monitor.plist
```

## How It Works

### Workflow Schedule
- Runs **every hour** at minute 5 (e.g., 1:05, 2:05, 3:05, etc.)
- Can also be triggered manually from the Actions tab

### What It Does
1. Checks out the repository
2. Installs Azure CLI and dependencies (jq, bc)
3. Logs into Azure using service principal
4. Runs `dashboard/collect-data.sh`
5. Commits updated `data.json` back to the repo
6. GitHub Pages automatically updates the dashboard

### Accessing the Dashboard

**Public URL:** https://satishgonella2024.github.io/cloud-finops/dashboard/

- No need to start a local web server
- Access from any device (phone, tablet, laptop)
- Always shows latest data (auto-refreshes every hour)
- Share with others if needed

## Service Principal Details

A dedicated service principal has been created for GitHub Actions:

- **Name:** `github-actions-azure-monitor`
- **Role:** Reader (subscription level)
- **Access:** Read-only access to metrics, resources, and billing data
- **Security:** Credentials stored securely in GitHub Secrets

## Troubleshooting

### Workflow fails with "Azure login failed"
- Verify `AZURE_CREDENTIALS` secret is set correctly in GitHub Settings
- Check that the service principal still exists: `az ad sp show --id 9147ddf5-6e32-441e-ae7a-dceae2c89009`

### Dashboard shows old data
- Check the Actions tab to see if the workflow is running successfully
- Verify commits are being made to `dashboard/data.json`
- Hard refresh the dashboard page (Cmd+Shift+R on Mac, Ctrl+Shift+R on Windows)

### Workflow succeeds but no commit
- This is normal if data hasn't changed
- The workflow only commits when `data.json` actually changes

### Invoice data missing
- The service principal has Reader access but may need additional billing permissions
- If invoices stop appearing, run this command locally and commit the result:
  ```bash
  ./dashboard/collect-data.sh
  git add dashboard/data.json
  git commit -m "Manual data update"
  git push
  ```

## Benefits Over Local Mac Setup

| Feature | Local Mac | GitHub Actions |
|---------|-----------|----------------|
| Always running | ❌ Only when Mac is on | ✅ 24/7 |
| Remote access | ❌ Only on local network | ✅ Anywhere via HTTPS |
| Mobile access | ❌ No | ✅ Yes |
| Reliability | ❌ Stops if Mac sleeps | ✅ Runs in cloud |
| Data backup | ❌ Manual | ✅ Automatic (Git history) |
| Cost | Free | Free |

## Reverting to Local Setup

If you want to go back to the local Mac setup:

1. Re-enable the LaunchAgent:
   ```bash
   launchctl load ~/Library/LaunchAgents/com.azure.usage-monitor.plist
   ```

2. Disable the GitHub Actions workflow:
   - Go to `.github/workflows/collect-azure-data.yml`
   - Delete it or rename to `collect-azure-data.yml.disabled`

3. Start the local dashboard:
   ```bash
   cd /Users/satish/qlp-projects/azure-monitor/dashboard
   python3 -m http.server 8847
   ```
