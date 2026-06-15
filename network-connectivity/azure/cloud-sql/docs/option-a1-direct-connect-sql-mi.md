# Option A1: Direct Connect — Azure SQL Managed Instance

> Simplest possible setup. Devin connects directly to Azure SQL MI using a standard SQL connection string -- no service principal, no Azure identity.

## Overview

Devin connects to Azure SQL Managed Instance using a standard TDS connection string over TLS. No Azure CLI, no service principal, no special binaries. The only credential on Devin is a SQL auth user and password.

Azure SQL MI **always enforces TLS** -- transport encryption is guaranteed.

SQL MI is VNet-integrated by default and does not have a public endpoint unless explicitly enabled. You must either enable the public endpoint or provide a network path from Devin to the MI's VNet (e.g., Zscaler ZPA, VPN Gateway).

## Prerequisites

- An Azure SQL Managed Instance with **public endpoint enabled** (or reachable via Zscaler ZPA / VPN)
- Network path from Devin to the MI endpoint
- Devin org admin access to configure secrets

## Customer Setup (Azure Side)

### 1. Enable Public Endpoint (if needed)

```bash
# Enable public endpoint on the MI
az sql mi update \
  --resource-group RESOURCE_GROUP \
  --name MI_NAME \
  --public-data-endpoint-enabled true
```

The public endpoint uses port **3342** (not 1433). The hostname format is:
`MI_NAME.public.HASH.database.windows.net,3342`

### 2. Configure Network Security

**If using the public endpoint:**

Add Devin's static egress IPs to the MI subnet's Network Security Group (NSG):

```bash
# Add inbound rule for Devin egress IPs on port 3342
# Full IP list: https://docs.devin.ai/admin/common-issues#ip-whitelisting
az network nsg rule create \
  --resource-group RESOURCE_GROUP \
  --nsg-name MI_SUBNET_NSG \
  --name allow-devin-sql-mi \
  --priority 200 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 3342 \
  --source-address-prefixes DEVIN_IP_1 DEVIN_IP_2
```

**If using Zscaler ZPA or VPN Gateway:**
- Route Devin traffic to the MI's VNet-internal endpoint (`MI_NAME.HASH.database.windows.net:1433`)
- No public endpoint needed

### 3. Create the Database User

```sql
-- Create a server-level login
CREATE LOGIN devin_dev WITH PASSWORD = 'SECURE_PASSWORD';

-- Switch to the target database
USE target_database;

-- Create a database user mapped to the login
CREATE USER devin_dev FOR LOGIN devin_dev;

-- Grant read access across all tables
ALTER ROLE db_datareader ADD MEMBER devin_dev;

-- Grant selective write access on application schema
GRANT INSERT, UPDATE, DELETE ON SCHEMA::app_schema TO devin_dev;

-- Explicit deny on DDL operations
DENY CREATE TABLE TO devin_dev;
DENY ALTER ANY SCHEMA TO devin_dev;
```

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | MI public endpoint (or VNet-internal hostname via network path) | `mi-name.public.abc123.database.windows.net,3342` |
| `DB_USER` | SQL auth username | `devin_dev` |
| `DB_PASSWORD` | SQL auth password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

**Note:** For the public endpoint, include the port `,3342` in `DB_HOST`. For VNet-internal access via Zscaler/VPN, use port 1433 (the default).

### 2. Environment Blueprint

See [examples/blueprint-direct-connect-sql-mi.yaml](../examples/blueprint-direct-connect-sql-mi.yaml).

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Azure SQL MI) is at $DB_HOST.
      Connect with: sqlcmd -S $DB_HOST -d $DB_NAME -U $DB_USER -P $DB_PASSWORD
      Connection string: Server=tcp:$DB_HOST;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;
      TLS is always enforced by Azure SQL MI.
```

No `initialize` or `maintenance` commands needed.

### 3. MCP Server (Optional)

Enable the SQL Server MCP server in Settings > MCP Marketplace:
- Connection string: `Server=tcp:$DB_HOST;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;`

## Validation

```bash
# From a Devin session:
sqlcmd -S "$DB_HOST" -d "$DB_NAME" -U "$DB_USER" -P "$DB_PASSWORD"

# Verify TLS is active
SELECT encrypt_option FROM sys.dm_exec_connections WHERE session_id = @@SPID;
GO
-- Should return 'TRUE'

# Test read access
SELECT TOP 5 * FROM shared_schema.some_table;
GO

# Test write access
INSERT INTO app_schema.test_table (col) VALUES ('test');
DELETE FROM app_schema.test_table WHERE col = 'test';
GO
```

## Security Properties

| Property | Status |
|---|---|
| Azure credentials on Devin | **None** -- SQL auth password only |
| Secret rotation required | **No Azure key** -- DB password should be rotated every 90 days |
| Transport encryption | TLS (always enforced by Azure SQL MI) |
| Blast radius if Devin secret leaks | Scoped DB user/password -- limited to granted schemas |
| Audit trail | Azure SQL audit logs show `devin_dev` queries |

## When to Upgrade to Option B or C

Consider upgrading if:
- You need to disable the MI's public endpoint
- Your security policy requires Entra ID token-based authentication (not just DB passwords)
- You want short-lived tokens instead of long-lived passwords
- You're moving from POC to production
