# Option C1: Customer-Hosted Private Endpoint — Azure SQL Managed Instance

> Keep all Azure identity on the customer side. Devin holds only a scoped database password.

## Overview

Azure SQL MI is already deployed inside a customer VNet with a private IP address. The customer exposes this VNet-internal endpoint to Devin through an existing network path (typically Zscaler ZPA or VPN Gateway). Devin authenticates with a standard SQL auth user and password.

This mirrors how human developers typically access the database: through a corporate zero-trust network, authenticating with DB credentials, without holding Azure service principal secrets on their machines.

**Note:** Unlike PostgreSQL Flexible Server, SQL MI does not need a separate Private Endpoint resource — it is natively VNet-integrated. The "private endpoint" here refers to the MI's existing VNet-internal address exposed to Devin via the network path.

## Prerequisites

- An Azure SQL Managed Instance (VNet-integrated)
- A network path from Devin to the customer's Azure VNet (Zscaler ZPA recommended)
- Devin org admin access to configure secrets

## Customer Setup (Azure Side)

### 1. Identify the MI VNet-Internal Endpoint

```bash
# Get the MI's VNet-internal FQDN
az sql mi show \
  --resource-group RESOURCE_GROUP \
  --name MI_NAME \
  --query fullyQualifiedDomainName -o tsv
# Returns: mi-name.abc123.database.windows.net
```

The VNet-internal endpoint uses port **1433** (the default TDS port).

### 2. Configure Network Access to the MI VNet

**If using Zscaler ZPA:**
- Add the MI's VNet-internal FQDN and IP as a ZPA Application Segment
- Protocol: TCP, Port: 1433
- Assign access policy consistent with existing Devin application segments

**If using VPN Gateway:**
- Ensure the MI's delegated subnet is routable from the VPN Gateway
- Configure DNS forwarding so `MI_NAME.abc123.database.windows.net` resolves to the MI's private IP

### 3. Ensure Public Endpoint Is Disabled (Recommended)

```bash
# Verify public endpoint is disabled
az sql mi show \
  --resource-group RESOURCE_GROUP \
  --name MI_NAME \
  --query publicDataEndpointEnabled -o tsv
# Should return "false"
```

### 4. Create the Database User

```sql
-- Create a server-level login
CREATE LOGIN devin_dev WITH PASSWORD = 'SECURE_PASSWORD';

-- Switch to the target database
USE target_database;

-- Create a database user
CREATE USER devin_dev FOR LOGIN devin_dev;

-- Grant read access
ALTER ROLE db_datareader ADD MEMBER devin_dev;

-- Grant selective write access
GRANT INSERT, UPDATE, DELETE ON SCHEMA::app_schema TO devin_dev;

-- Deny DDL
DENY CREATE TABLE TO devin_dev;
DENY ALTER ANY SCHEMA TO devin_dev;
```

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | MI VNet-internal FQDN (Zscaler-reachable) | `mi-name.abc123.database.windows.net` |
| `DB_USER` | SQL auth username | `devin_dev` |
| `DB_PASSWORD` | SQL auth password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

No `initialize` or `maintenance` commands needed if `sqlcmd` is already available. If not, install it in `initialize`:

```yaml
initialize: |
  # Install sqlcmd (if not already available)
  curl -sSL https://packages.microsoft.com/keys/microsoft.asc | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc > /dev/null
  echo "deb [arch=amd64] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/mssql-release.list
  sudo apt-get update
  sudo ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev
  echo 'export PATH="$PATH:/opt/mssql-tools18/bin"' >> ~/.bashrc

knowledge:
  - name: database
    contents: |
      Dev database (Azure SQL MI) is at $DB_HOST:1433.
      Connect with: sqlcmd -S $DB_HOST -d $DB_NAME -U $DB_USER -P $DB_PASSWORD
      Connection string: Server=tcp:$DB_HOST,1433;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;
      TLS is always enforced by Azure SQL MI.
```

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

# Verify DDL is denied (expected failure)
CREATE TABLE app_schema.bad_table (id INT);
GO
-- ERROR: permission denied
```

## Security Properties

| Property | Status |
|---|---|
| Azure credentials on Devin | **None** |
| Secret rotation required | **DB password only** -- every 90 days or on personnel change |
| Transport encryption | TLS (always enforced by SQL MI) + Zscaler/VPN encryption |
| Blast radius if Devin secret leaks | Scoped DB user/password only -- no Azure AD access |
| Audit trail | Azure SQL audit logs show `devin_dev` queries; Zscaler logs show network access |
