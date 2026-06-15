# Option B1: Service Principal — Azure Database for PostgreSQL

> Entra ID service principal credentials stored as Devin secrets, Entra ID token acquired at session start for token-based PostgreSQL authentication.

## Overview

The customer creates an Entra ID (Azure AD) app registration and service principal, provides the client ID and secret to the Devin org admin, and they are stored as Devin org-scoped secrets. Each Devin session uses these credentials to acquire an Entra ID access token for `https://ossrdbms-aad.database.windows.net`, then connects to Azure Database for PostgreSQL using token-based authentication (the token replaces the password in the connection string).

Token-based auth means no PostgreSQL password is needed -- the Entra ID token acts as the credential, and it expires after ~1 hour (auto-refreshed by the Azure CLI or application code).

## Prerequisites

- An Azure subscription with an Azure Database for PostgreSQL Flexible Server
- Entra ID (Azure AD) tenant with permissions to create app registrations
- An Entra ID admin set as the Flexible Server's AD administrator
- Network path from Devin to the Flexible Server (internet access for public endpoint; Zscaler ZPA for private endpoint)
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

### 2. Set Entra ID Admin on Flexible Server

An Entra ID admin must be configured on the Flexible Server to enable Entra ID authentication:

```bash
az postgres flexible-server ad-admin create \
  --resource-group RESOURCE_GROUP \
  --server-name PG_SERVER_NAME \
  --display-name "PG Admin" \
  --object-id ADMIN_OBJECT_ID \
  --type ServicePrincipal
```

### 3. Create the PostgreSQL Role for the Service Principal

Connect to the database as the Entra ID admin and create a role mapped to the service principal:

```sql
-- Enable the pgaadauth extension (if not already enabled)
-- This may require a server parameter change via Azure Portal or CLI:
-- az postgres flexible-server parameter set \
--   --resource-group RESOURCE_GROUP \
--   --server-name PG_SERVER_NAME \
--   --name azure.extensions \
--   --value pgaadauth

-- Create a role mapped to the service principal's display name
SELECT * FROM pgaadauth_create_principal('devin-db-sp', false, false);

-- Grant schema-scoped permissions
GRANT USAGE ON SCHEMA app_schema TO "devin-db-sp";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO "devin-db-sp";
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "devin-db-sp";

GRANT USAGE ON SCHEMA shared_schema TO "devin-db-sp";
GRANT SELECT ON ALL TABLES IN SCHEMA shared_schema TO "devin-db-sp";
ALTER DEFAULT PRIVILEGES IN SCHEMA shared_schema
  GRANT SELECT ON TABLES TO "devin-db-sp";
```

### 4. Configure Network Access

**If the Flexible Server has a public endpoint:**
- Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to the Flexible Server firewall
- Or route through Zscaler ZPA

**If using a Private Endpoint:**
- Ensure Devin can reach the private endpoint via Zscaler ZPA or VPN Gateway

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Notes |
|---|---|---|
| `AZURE_TENANT_ID` | Entra ID tenant ID | GUID |
| `AZURE_CLIENT_ID` | Service principal app ID | GUID |
| `AZURE_CLIENT_SECRET` | Service principal client secret | Shown only at creation |
| `PG_HOST` | Flexible Server hostname | `server.postgres.database.azure.com` |
| `DB_NAME` | Database name | e.g., `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-service-principal-postgresql.yaml](../examples/blueprint-service-principal-postgresql.yaml) for the full blueprint.

```yaml
initialize: |
  curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

maintenance: |
  az login --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --password "$AZURE_CLIENT_SECRET" \
    --tenant "$AZURE_TENANT_ID" \
    --output none

  az account get-access-token \
    --resource-type oss-rdbms \
    --query accessToken -o tsv > /dev/shm/azure-pg-token
  chmod 600 /dev/shm/azure-pg-token

knowledge:
  - name: database
    contents: |
      Azure PostgreSQL dev database is available at $PG_HOST:5432 via Entra ID token auth.
      Entra ID token location: /dev/shm/azure-pg-token
      Connect with psql: PGPASSWORD=$(cat /dev/shm/azure-pg-token) psql -h $PG_HOST -p 5432 -U devin-db-sp -d $DB_NAME
      Token expires in ~1 hour. Refresh: az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv
```

### 3. MCP Server (Optional)

Enable the PostgreSQL MCP server in Settings > MCP Marketplace. For Entra ID token auth, pass the token as the password:
- Host: `$PG_HOST`
- Database: `$DB_NAME`
- User: `devin-db-sp`
- Password: contents of `/dev/shm/azure-pg-token`

## Validation

```bash
# Verify Azure CLI login
az account show --query "{tenant:tenantId, user:user.name}" -o table

# Verify token acquisition
cat /dev/shm/azure-pg-token | head -c 50
# Should show a JWT prefix (eyJ...)

# Connect with psql using Entra ID token as password
PGPASSWORD=$(cat /dev/shm/azure-pg-token) psql \
  -h "$PG_HOST" -p 5432 -U "devin-db-sp" -d "$DB_NAME"

# Verify TLS is active
SELECT ssl_is_used();
-- Should return 't'

# Test queries
SELECT * FROM app_schema.some_table LIMIT 5;
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
| Transport encryption | TLS (enforced by Flexible Server) |
| Blast radius if Devin secret leaks | Service principal with scoped DB access only -- no subscription-level permissions |
| Audit trail | Entra ID sign-in logs show SP authentication; Azure PostgreSQL audit logs show queries |
