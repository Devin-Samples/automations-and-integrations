# Azure DevOps Webhook Receiver for Devin

An Azure Function that receives [Azure DevOps service hook](https://learn.microsoft.com/en-us/azure/devops/service-hooks/overview) payloads and creates [Devin](https://devin.ai) sessions when a work item is tagged with a configurable trigger tag (default: `Devin:Discovery`).

## Architecture

```
Azure DevOps                     Azure Function                  Devin API
┌─────────────┐   HTTP POST     ┌──────────────────┐  POST     ┌─────────────┐
│ Work item    │ ─────────────> │ devops-webhook    │ ───────> │ /v3/.../     │
│ tagged with  │  service hook  │                    │          │  sessions    │
│ Devin:       │                │ 1. Parse payload   │          │              │
│ Discovery    │                │ 2. Check tag       │          │ Creates new  │
│              │                │ 3. Build prompt    │          │ Devin session│
└─────────────┘                └──────────────────┘          └─────────────┘
```

## How It Works

1. A work item in Azure DevOps is updated (e.g., a tag is added)
2. The service hook fires an HTTP POST to the Azure Function endpoint
3. The function parses the payload and checks for the trigger tag
4. If the tag is present, it builds a prompt from the work item's title and description
5. It calls the Devin API to create a new session with that prompt
6. If the tag is absent, the request is acknowledged but no session is created

## Prerequisites

- An Azure subscription ([free trial](https://azure.microsoft.com/free/))
- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) authenticated (`az login`)
- An Azure DevOps organization and project ([create one](https://dev.azure.com))
- An Azure DevOps [Personal Access Token (PAT)](https://learn.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate) with **Work Items** and **Project** read/write scopes
- A Devin API key and organization ID ([API quickstart](https://docs.devin.ai/api-reference/getting-started/teams-quickstart))

## Quick Start

### 1. Deploy the Azure Function

```bash
export DEVIN_API_KEY="cog_..."
export DEVIN_ORG_ID="org-..."

./scripts/deploy-function.sh rg-devin-integration devin-webhook-relay eastus
```

This creates:
- A resource group, storage account, and consumption-plan function app
- Configures `DEVIN_API_KEY` and `DEVIN_ORG_ID` as app settings
- Deploys the function code with remote build enabled

The script prints the webhook URL on completion (e.g., `https://devin-webhook-relay.azurewebsites.net/api/devops-webhook`).

### 2. Create the Service Hook

```bash
export AZURE_DEVOPS_PAT="your-pat-here"

./scripts/setup-service-hook.sh \
  "https://dev.azure.com/YourOrg" \
  "YourProject" \
  "https://devin-webhook-relay.azurewebsites.net/api/devops-webhook"
```

Or configure manually:
1. Go to **Project Settings > Service hooks** in Azure DevOps
2. Click **+ Create subscription**
3. Select **Web Hooks** as the service
4. Event: **Work item updated**
5. URL: paste your function's webhook URL

### 3. Test

```bash
./scripts/test-webhook.sh https://devin-webhook-relay.azurewebsites.net/api/devops-webhook
```

This sends three simulated payloads:
- **With** `Devin:Discovery` tag -> expects `session_created`
- **Without** tag -> expects `skipped`
- **Non-work-item event** -> expects `ignored`

### 4. Trigger End-to-End

In Azure DevOps, add the tag `Devin:Discovery` to any work item. A Devin session will be created with the work item's title and description as the prompt.

## File Structure

```
webhook-receiver/
├── function_app.py          # Azure Function entry point
├── host.json                # Azure Functions host configuration
├── requirements.txt         # Python dependencies
├── scripts/
│   ├── deploy-function.sh   # Deploy function app to Azure
│   ├── setup-service-hook.sh # Create service hook via REST API
│   └── test-webhook.sh      # Test with simulated payloads
└── README.md
```

## Configuration

| Environment Variable | Required | Default | Description |
|---|---|---|---|
| `DEVIN_API_KEY` | Yes | — | Devin API key (starts with `cog_`) |
| `DEVIN_ORG_ID` | Yes | — | Devin organization ID (starts with `org-`) |
| `DEVIN_TAG` | No | `Devin:Discovery` | Tag that triggers session creation (case-insensitive) |

### Customizing the Trigger Tag

Set the `DEVIN_TAG` app setting to change which tag triggers Devin sessions:

```bash
az functionapp config appsettings set \
  --name devin-webhook-relay \
  --resource-group rg-devin-integration \
  --settings DEVIN_TAG="Ready:Devin"
```

## Security Considerations

> **Warning:** The default deployment uses `AuthLevel.ANONYMOUS` (no function key required). This means anyone who discovers the URL can trigger Devin session creation. For production use, consider:
>
> - Adding a shared secret header validated in the function code
> - Using Azure API Management in front of the function
> - Restricting inbound IPs to Azure DevOps service hook IPs

## Devin API Reference

- [Create Session](https://docs.devin.ai/api-reference/v3/sessions/post-organizations-sessions) — `POST /v3/organizations/{org_id}/sessions`
- [API Overview](https://docs.devin.ai/api-reference/overview)

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| 404 on webhook URL | Function not deployed or still initializing | Wait 1-2 minutes after deploy; check `az functionapp show` |
| Service hook shows "failure" | URL unreachable or returning errors | Check function logs: `az functionapp log tail` |
| `skipped` response | Work item doesn't have the trigger tag | Verify tag spelling matches `DEVIN_TAG` (case-insensitive) |
| `error: DEVIN_API_KEY and DEVIN_ORG_ID must be set` | Missing app settings | Run `az functionapp config appsettings list` to check |
| 502 from function | Devin API call failed | Check API key validity and org ID |
