# Option C: Direct Connect

> Simplest possible setup. Devin connects directly to Azure SQL using a standard SQL connection string -- no service principal, no Azure identity.

## Overview

Devin connects to Azure SQL Database using a standard SQL connection string over TLS. No Azure CLI, no service principal, no special binaries. The only credential on Devin is a SQL auth user and password.

Azure SQL **always enforces TLS** -- there is no option to disable it. Even with this simplest option, transport encryption is guaranteed.

This is the fastest path to a working connection but provides fewer security layers than Options A or B.

## Prerequisites

- An Azure SQL Database with the **public endpoint enabled** (or reachable via Zscaler ZPA)
- Network path from Devin to the Azure SQL endpoint
- Devin org admin access to configure secrets

## Customer Setup (Azure Side)

### 1. Enable Public Network Access

Verify that the Azure SQL server allows public network access:

```bash
az sql server show \
  --resource-group RESOURCE_GROUP \
  --name SQL_SERVER_NAME \
  --query publicNetworkAccess -o tsv
# Should return "Enabled"
```

If disabled, enable it:

```bash
az sql server update \
  --resource-group RESOURCE_GROUP \
  --name SQL_SERVER_NAME \
  --public-network-access Enabled
```

### 2. Configure Firewall Rules

**Option A: Devin Static IPs**

```bash
# Add Devin's static egress IPs to the server firewall
# Full IP list: https://docs.devin.ai/admin/common-issues#ip-whitelisting
az sql server firewall-rule create \
  --resource-group RESOURCE_GROUP \
  --server SQL_SERVER_NAME \
  --name devin-egress-1 \
  --start-ip-address DEVIN_IP_1 \
  --end-ip-address DEVIN_IP_1

# Repeat for each Devin egress IP
```

**Option B: Zscaler ZPA**
- Add the Azure SQL server's public endpoint (`SERVER.database.windows.net:1433`) as a ZPA Application Segment

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
| `DB_HOST` | Azure SQL server public hostname | `server.database.windows.net` |
| `DB_USER` | SQL auth username | `devin_dev` |
| `DB_PASSWORD` | SQL auth password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-direct-connect.yaml](../examples/blueprint-direct-connect.yaml).

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Azure SQL) is at $DB_HOST:1433.
      Connect with: sqlcmd -S $DB_HOST -d $DB_NAME -U $DB_USER -P $DB_PASSWORD
      Connection string: Server=tcp:$DB_HOST,1433;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;
      TLS is always enforced by Azure SQL.
```

No `initialize` or `maintenance` commands needed -- `sqlcmd` and standard SQL client libraries are available in Devin sessions or easily installable.

### 3. MCP Server (Optional)

Enable the SQL Server MCP server in Settings > MCP Marketplace:
- Connection string: `Server=tcp:$DB_HOST,1433;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;`

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
| Transport encryption | TLS (always enforced by Azure SQL -- cannot be disabled) |
| Blast radius if Devin secret leaks | Scoped DB user/password -- limited to granted schemas |
| Audit trail | Azure SQL audit logs show `devin_dev` queries |

## When to Choose This Option

- You want the absolute fastest path to a working connection
- The database has a public endpoint and you're comfortable with IP allowlisting
- AAD token-based authentication is not required by your security policy
- You want to avoid installing additional tools (Azure CLI) in the Devin environment

## When to Upgrade to Option A or B

Consider upgrading if:
- You need to eliminate the Azure SQL public endpoint (move to Private Endpoint)
- Your security policy requires Azure AD authentication (not just SQL auth)
- You want short-lived tokens instead of long-lived passwords
- You're moving from POC to production
