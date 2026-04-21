#!/usr/bin/env bash
set -euo pipefail

# Create an Azure DevOps service hook that fires on work item updates.
#
# Usage:
#   ./scripts/setup-service-hook.sh <org-url> <project-name> <webhook-url>
#
# Prerequisites:
#   - AZURE_DEVOPS_PAT environment variable set with a valid PAT
#     (scopes: Work Items Read/Write, Project Read)
#   - WEBHOOK_SECRET environment variable set (same value configured on the
#     Azure Function). The secret is sent as an X-Webhook-Secret HTTP header
#     with every service hook request.
#
# Example:
#   export AZURE_DEVOPS_PAT="your-pat-here"
#   export WEBHOOK_SECRET="your-shared-secret"
#   ./scripts/setup-service-hook.sh \
#     "https://dev.azure.com/MyOrg" \
#     "MyProject" \
#     "https://my-func.azurewebsites.net/api/devops-webhook"

DEVOPS_ORG="${1:?Usage: $0 <org-url> <project-name> <webhook-url>}"
PROJECT_NAME="${2:?Usage: $0 <org-url> <project-name> <webhook-url>}"
WEBHOOK_URL="${3:?Usage: $0 <org-url> <project-name> <webhook-url>}"

if [ -z "${AZURE_DEVOPS_PAT:-}" ]; then
  echo "ERROR: AZURE_DEVOPS_PAT environment variable must be set"
  exit 1
fi

if [ -z "${WEBHOOK_SECRET:-}" ]; then
  echo "ERROR: WEBHOOK_SECRET environment variable must be set"
  echo "Generate one with: export WEBHOOK_SECRET=\"\$(openssl rand -hex 32)\""
  exit 1
fi

echo "=== Creating Azure DevOps Service Hook ==="
echo "Organization: $DEVOPS_ORG"
echo "Project:      $PROJECT_NAME"
echo "Webhook URL:  $WEBHOOK_URL"
echo ""

# Resolve project ID
PROJECT_ID=$(curl -s -u ":$AZURE_DEVOPS_PAT" \
  "${DEVOPS_ORG}/_apis/projects/${PROJECT_NAME}?api-version=7.1" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")

echo "Project ID: $PROJECT_ID"

# Create service hook subscription
RESPONSE=$(curl -s -X POST \
  -u ":$AZURE_DEVOPS_PAT" \
  -H "Content-Type: application/json" \
  -d "{
    \"publisherId\": \"tfs\",
    \"eventType\": \"workitem.updated\",
    \"resourceVersion\": \"1.0\",
    \"consumerId\": \"webHooks\",
    \"consumerActionId\": \"httpRequest\",
    \"publisherInputs\": {
      \"projectId\": \"$PROJECT_ID\"
    },
    \"consumerInputs\": {
      \"url\": \"$WEBHOOK_URL\",
      \"httpHeaders\": \"X-Webhook-Secret: $WEBHOOK_SECRET\",
      \"resourceDetailsToSend\": \"All\",
      \"messagesToSend\": \"All\",
      \"detailedMessagesToSend\": \"All\"
    }
  }" \
  "${DEVOPS_ORG}/_apis/hooks/subscriptions?api-version=7.1")

HOOK_ID=$(echo "$RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id','ERROR'))" 2>/dev/null || echo "ERROR")

if [ "$HOOK_ID" != "ERROR" ] && [ -n "$HOOK_ID" ]; then
  echo ""
  echo "Service hook created successfully!"
  echo "  Hook ID: $HOOK_ID"
  echo ""
  echo "The hook will fire when any work item in '$PROJECT_NAME' is updated."
  echo "Tag a work item with 'Devin:Implementation' to trigger a Devin session."
else
  echo "ERROR: Service hook creation failed. Response:"
  echo "$RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$RESPONSE"
  exit 1
fi
