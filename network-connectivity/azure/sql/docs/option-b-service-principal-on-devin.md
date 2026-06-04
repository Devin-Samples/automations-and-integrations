# Option B: Service Principal on Devin

> Fastest to stand up for POC. Azure AD service principal credentials stored as Devin secrets, AAD token acquired at session start for token-based SQL authentication.

## Overview

The customer creates an Azure AD (Entra ID) app registration and service principal, provides the client ID and secret to the Devin org admin, and they are stored as Devin org-scoped secrets. Each Devin session uses these credentials to acquire an Azure AD access token for `https://database.windows.net/`, then connects to Azure SQL using token-based authentication.

Token-based auth means no SQL password is needed -- the AAD token acts as the credential, and it expires after ~1 hour (auto-refreshed by the Azure CLI or application code).

## Prerequisites

- An Azure subscription with an Azure SQL Database
- Azure AD (Entra ID) tenant with permissions to create app registrations
- An Azure AD admin set as the Azure SQL server's AD administrator
- Network path from Devin to Azure SQL (internet access for public endpoint; Zscaler ZPA for private endpoint)
- Devin org admin access to configure secrets and environment blueprints

## Customer Setup (Azure Side)

### 1. Create the App Registration and Service Principal

```bash
# Create app registration
az ad app create --display-name "devin-db-sp"

# Note the appId from the output, then create a service principal
az ad sp create --id APP_ID

# Generate a client secret (store securely -- shown only once)
az ad app credential reset \
  --id APP_ID \
  --append \
  --display-name "devin-db-secret" \
  --years 1
```

Note the following from the output:
- `appId` -- this is the `AZURE_CLIENT_ID`
- `password` -- this is the `AZURE_CLIENT_SECRET`
- `tenant` -- this is the `AZURE_TENANT_ID`

### 2. Set Azure AD Admin on SQL Server

An Azure AD admin must be configured on the SQL server to enable AAD authentication:

```bash
# Set an Azure AD admin (a user or group) on the SQL server
az sql server ad-admin create \
  --resource-group RESOURCE_GROUP \
  --server-name SQL_SERVER_NAME \
  --display-name "SQL Admin" \
  --object-id ADMIN_OBJECT_ID
```

### 3. Create the Contained Database User

Connect to the target database as the Azure AD admin and create a contained user mapped to the service principal:

```sql
-- Create external user mapped to the service principal
-- Use the app registration's display name
CREATE USER [devin-db-sp] FROM EXTERNAL PROVIDER;

-- Grant read access
ALTER ROLE db_datareader ADD MEMBER [devin-db-sp];

-- Grant selective write access on application schema
GRANT INSERT, UPDATE, DELETE ON SCHEMA::app_schema TO [devin-db-sp];

-- Explicit deny on DDL
DENY CREATE TABLE TO [devin-db-sp];
DENY ALTER ANY SCHEMA TO [devin-db-sp];
```

### 4. Configure Network Access

**If the SQL server has a public endpoint:**
- Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to the Azure SQL server firewall
- Or route through Zscaler ZPA

**If using a Private Endpoint:**
- Ensure Devin can reach the private endpoint via Zscaler ZPA or VPN Gateway

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Notes |
|---|---|---|
| `AZURE_TENANT_ID` | Azure AD tenant ID | GUID |
| `AZURE_CLIENT_ID` | Service principal app ID | GUID |
| `AZURE_CLIENT_SECRET` | Service principal client secret | Shown only at creation |
| `AZURE_SQL_SERVER` | Azure SQL server hostname | `server.database.windows.net` |
| `DB_NAME` | Database name | e.g., `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-service-principal.yaml](../examples/blueprint-service-principal.yaml) for the full blueprint.

```yaml
initialize: |
  # Install Azure CLI (persists in snapshot)
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

maintenance: |
  # Log in as service principal
  az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" \
    --output none

  # Acquire AAD token for Azure SQL and write to tmpfs
  # /dev/shm is always tmpfs on Linux -- never captured in VM snapshots.
  az account get-access-token \
    --resource https://database.windows.net/ \
    --query accessToken -o tsv > /dev/shm/azure-sql-token
  chmod 600 /dev/shm/azure-sql-token

knowledge:
  - name: database
    contents: |
      Azure SQL dev database is available at $AZURE_SQL_SERVER:1433.
      AAD token for SQL auth: cat /dev/shm/azure-sql-token
      Connect with sqlcmd (AAD token): sqlcmd -S $AZURE_SQL_SERVER -d $DB_NAME -G --access-token $(cat /dev/shm/azure-sql-token)
      For pyodbc, use the token as the password with attrs_before={1256: token_bytes}.
      Token expires in ~1 hour. Re-run: az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
```

### 3. MCP Server (Optional)

Enable the SQL Server MCP server in Settings > MCP Marketplace. For AAD token auth, pass the token as the connection password:
- Server: `$AZURE_SQL_SERVER`
- Database: `$DB_NAME`
- Authentication: Token-based (provider-dependent configuration)

## Validation

```bash
# From a Devin session:

# Verify Azure CLI login
az account show --query "{tenant:tenantId, user:user.name}" -o table

# Verify token acquisition
cat /dev/shm/azure-sql-token | head -c 50
# Should show a JWT prefix (eyJ...)

# Connect with sqlcmd using AAD token
sqlcmd -S "$AZURE_SQL_SERVER" -d "$DB_NAME" -G \
  --access-token "$(cat /dev/shm/azure-sql-token)"

# Test queries
SELECT TOP 5 * FROM app_schema.some_table;
GO
```

## Client Secret Rotation

Azure AD client secrets should be rotated per your organization's policy:

1. Generate a new client secret:
   ```bash
   az ad app credential reset \
     --id APP_ID \
     --append \
     --display-name "devin-db-secret-v2" \
     --years 1
   ```
2. Update the `AZURE_CLIENT_SECRET` Devin Secret with the new value
3. Remove the old secret:
   ```bash
   az ad app credential delete --id APP_ID --key-id OLD_KEY_ID
   ```

## Security Properties

| Property | Status |
|---|---|
| Azure credentials on Devin | SP client ID + secret in Devin Secrets (encrypted, stripped from snapshots) |
| Secret rotation required | **Yes** -- per org policy (recommended: 6 months) |
| Transport encryption | TLS (always enforced by Azure SQL) |
| Blast radius if Devin secret leaks | Service principal with scoped DB access only -- no subscription-level permissions |
| Audit trail | Azure AD sign-in logs show SP authentication; Azure SQL audit logs show queries |
