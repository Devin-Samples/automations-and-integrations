#!/usr/bin/env bash
set -euo pipefail

# Deploy the Azure Function webhook relay to Azure.
#
# Usage:
#   ./scripts/deploy-function.sh <resource-group> <function-app-name> [location]
#
# Prerequisites:
#   - Azure CLI authenticated (`az login`)
#   - DEVIN_API_KEY and DEVIN_ORG_ID environment variables set
#
# Example:
#   export DEVIN_API_KEY="cog_..."
#   export DEVIN_ORG_ID="org-..."
#   ./scripts/deploy-function.sh rg-devin-integration devin-webhook-relay eastus

RESOURCE_GROUP="${1:?Usage: $0 <resource-group> <function-app-name> [location]}"
FUNC_APP_NAME="${2:?Usage: $0 <resource-group> <function-app-name> [location]}"
LOCATION="${3:-eastus}"
STORAGE_ACCOUNT="${FUNC_APP_NAME//-/}sa"
STORAGE_ACCOUNT="${STORAGE_ACCOUNT:0:24}"

echo "=== Deploying Azure Function Webhook Relay ==="
echo "Resource Group:  $RESOURCE_GROUP"
echo "Function App:    $FUNC_APP_NAME"
echo "Location:        $LOCATION"
echo "Storage Account: $STORAGE_ACCOUNT"
echo ""

echo "Creating resource group..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

echo "Creating storage account..."
az storage account create \
  --name "$STORAGE_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --output none

echo "Creating function app..."
az functionapp create \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --storage-account "$STORAGE_ACCOUNT" \
  --consumption-plan-location "$LOCATION" \
  --runtime python \
  --runtime-version 3.11 \
  --functions-version 4 \
  --os-type Linux \
  --output none

echo "Configuring app settings..."
if [ -z "${DEVIN_API_KEY:-}" ] || [ -z "${DEVIN_ORG_ID:-}" ]; then
  echo "WARNING: DEVIN_API_KEY and/or DEVIN_ORG_ID not set."
  echo "Set them manually:"
  echo "  az functionapp config appsettings set \\"
  echo "    --name $FUNC_APP_NAME \\"
  echo "    --resource-group $RESOURCE_GROUP \\"
  echo "    --settings DEVIN_API_KEY=<key> DEVIN_ORG_ID=<org-id>"
else
  SETTINGS="DEVIN_API_KEY=$DEVIN_API_KEY DEVIN_ORG_ID=$DEVIN_ORG_ID"
  if [ -n "${DEVIN_TAG:-}" ]; then
    SETTINGS="$SETTINGS DEVIN_TAG=$DEVIN_TAG"
  fi
  az functionapp config appsettings set \
    --name "$FUNC_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --settings $SETTINGS \
    --output none
  echo "App settings configured."
fi

# Enable remote build for Python dependency installation
az functionapp config appsettings set \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --settings \
    "SCM_DO_BUILD_DURING_DEPLOYMENT=true" \
    "ENABLE_ORYX_BUILD=true" \
  --output none

echo "Deploying function code..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNC_DIR="$SCRIPT_DIR/.."

DEPLOY_ZIP="/tmp/function-deploy-$$.zip"
(cd "$FUNC_DIR" && zip -r "$DEPLOY_ZIP" . \
  -x "scripts/*" \
  -x "local.settings.json" \
  -x ".venv/*" \
  -x "__pycache__/*" \
  -x "*.md")

az functionapp deployment source config-zip \
  --name "$FUNC_APP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --src "$DEPLOY_ZIP" \
  --build-remote true \
  --output none

rm -f "$DEPLOY_ZIP"

echo ""
echo "=== Deployment Complete ==="
FUNC_URL="https://${FUNC_APP_NAME}.azurewebsites.net/api/devops-webhook"
echo "Webhook URL: $FUNC_URL"
echo ""
echo "Use this URL when configuring the Azure DevOps service hook."
