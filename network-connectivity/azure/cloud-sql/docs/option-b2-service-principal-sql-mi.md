# Option B2: Service Principal — Azure SQL Managed Instance

> Entra ID service principal credentials stored as Devin secrets, Entra ID token acquired at session start for token-based SQL MI authentication.

## Overview

The customer creates an Entra ID (Azure AD) app registration and service principal, provides the client ID and secret to the Devin org admin, and they are stored as Devin org-scoped secrets. Each Devin session uses these credentials to acquire an Entra ID access token for `https://database.windows.net/`, then connects to Azure SQL MI using token-based authentication (the token replaces the password in the connection string).

Token-based auth means no SQL password is needed -- the Entra ID token acts as the credential, and it expires after ~1 hour (auto-refreshed by the Azure CLI or application code).

## Prerequisites

- An Azure SQL Managed Instance
- Entra ID (Azure AD) tenant with permissions to create app registrations
- An Entra ID admin set as the MI's AD administrator
- Network path from Devin to the MI (public endpoint, or Zscaler ZPA / VPN to the MI VNet)
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

### 2. Set Entra ID Admin on the Managed Instance

An Entra ID admin must be configured on the MI to enable Entra ID authentication:

```bash
az sql mi ad-admin create \
  --resource-group RESOURCE_GROUP \
  --managed-instance MI_NAME \
  --display-name "MI Admin" \
  --object-id ADMIN_OBJECT_ID
```

### 3. Create the Contained Database User for the Service Principal

Connect to the MI database as the Entra ID admin and create an external user mapped to the service principal:

```sql
-- In the target database:
CREATE USER [devin-db-sp] FROM EXTERNAL PROVIDER;

-- Grant read access
ALTER ROLE db_datareader ADD MEMBER [devin-db-sp];

-- Grant selective write access
GRANT INSERT, UPDATE, DELETE ON SCHEMA::app_schema TO [devin-db-sp];

-- Deny DDL
DENY CREATE TABLE TO [devin-db-sp];
DENY ALTER ANY SCHEMA TO [devin-db-sp];
```

### 4. Configure Network Access

**If using the public endpoint:**

```bash
# Enable public endpoint on the MI
az sql mi update \
  --resource-group RESOURCE_GROUP \
  --name MI_NAME \
  --public-data-endpoint-enabled true
```

Add Devin's static egress IPs to the MI subnet's NSG on port 3342.

**If using Zscaler ZPA or VPN Gateway:**
- Route Devin traffic to the MI's VNet-internal endpoint (`MI_NAME.HASH.database.windows.net:1433`)

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Notes |
|---|---|---|
| `AZURE_TENANT_ID` | Entra ID tenant ID | GUID |
| `AZURE_CLIENT_ID` | Service principal app ID | GUID |
| `AZURE_CLIENT_SECRET` | Service principal client secret | Shown only at creation |
| `MI_HOST` | MI endpoint hostname | `mi-name.public.abc123.database.windows.net,3342` (public) or `mi-name.abc123.database.windows.net` (VNet) |
| `DB_NAME` | Database name | e.g., `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-service-principal-sql-mi.yaml](../examples/blueprint-service-principal-sql-mi.yaml) for the full blueprint.

```yaml
initialize: |
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
  # Install sqlcmd (Microsoft ODBC tools)
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null
  echo "deb [arch=amd64] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mssql-release.list
  sudo apt-get update
  sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev
  echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc

maintenance: |
  export PATH="$PATH:/opt/mssql-tools18/bin"

  az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" \
    --output none

  # Acquire Entra ID token for Azure SQL and write to tmpfs
  az account get-access-token \
    --resource https://database.windows.net/ \
    --query accessToken -o tsv > /dev/shm/azure-sql-token
  chmod 600 /dev/shm/azure-sql-token

knowledge:
  - name: database
    contents: |
      Azure SQL MI dev database is available at $MI_HOST via Entra ID token auth.
      Entra ID token location: /dev/shm/azure-sql-token
      Connect with sqlcmd: sqlcmd -S $MI_HOST -d $DB_NAME -G -P $(cat /dev/shm/azure-sql-token)
      Token expires in ~1 hour. Refresh: az account get-access-token --resource https://database.windows.net/ --query accessToken -o tsv
```

### 3. MCP Server (Optional)

Enable the SQL Server MCP server in Settings > MCP Marketplace. For Entra ID token auth, pass the token as the password:
- Server: `$MI_HOST`
- Database: `$DB_NAME`
- Authentication: Entra ID token from `/dev/shm/azure-sql-token`

## Validation

```bash
# Verify Azure CLI login
az account show --query "{tenant:tenantId, user:user.name}" -o table

# Verify token acquisition
cat /dev/shm/azure-sql-token | head -c 50
# Should show a JWT prefix (eyJ...)

# Connect with sqlcmd using Entra ID token
sqlcmd -S "$MI_HOST" -d "$DB_NAME" -G -P "$(cat /dev/shm/azure-sql-token)"

# Verify TLS is active
SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id = @@SPID;
GO
-- Should return 'TRUE'

# Test queries
SELECT TOP 5 * FROM app_schema.some_table;
GO
```

## Client Secret Rotation

Entra ID client secrets should be rotated per your organization's policy:

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
| Transport encryption | TLS (always enforced by Azure SQL MI) |
| Blast radius if Devin secret leaks | Service principal with scoped DB access only -- no subscription-level permissions |
| Audit trail | Entra ID sign-in logs show SP authentication; Azure SQL audit logs show queries |
