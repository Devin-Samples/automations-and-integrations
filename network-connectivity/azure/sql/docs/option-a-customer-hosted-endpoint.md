# Option A: Customer-Hosted Private Endpoint

> Keep all Azure identity on the customer side. Devin holds only a scoped SQL auth password.

## Overview

The customer creates an Azure Private Endpoint for their Azure SQL logical server, making it reachable via a private IP within their VNet. Devin reaches this private endpoint through the existing network path (typically Zscaler ZPA or ExpressRoute) and authenticates with a standard SQL auth user and password.

This mirrors how human developers typically access the database: through a corporate zero-trust network to a database endpoint, authenticating with DB credentials, without holding Azure service principal secrets on their machines.

## Prerequisites

- An Azure subscription with an Azure SQL Database (logical server + database)
- A VNet with a subnet available for the private endpoint
- A network path from Devin to the customer's Azure VNet (Zscaler ZPA recommended)
- Devin org admin access to configure secrets

## Customer Setup (Azure Side)

### 1. Create the Private Endpoint

```bash
# Create a private endpoint for Azure SQL in an existing subnet
az network private-endpoint create \
  --resource-group RESOURCE_GROUP \
  --name devin-sql-pe \
  --vnet-name VNET_NAME \
  --subnet SUBNET_NAME \
  --private-connection-resource-id $(az sql server show \
    --resource-group RESOURCE_GROUP \
    --name SQL_SERVER_NAME \
    --query id -o tsv) \
  --group-id sqlServer \
  --connection-name devin-sql-connection
```

### 2. Configure Private DNS (Recommended)

```bash
# Create private DNS zone for Azure SQL
az network private-dns zone create \
  --resource-group RESOURCE_GROUP \
  --name privatelink.database.windows.net

# Link DNS zone to VNet
az network private-dns zone-link vnet create \
  --resource-group RESOURCE_GROUP \
  --zone-name privatelink.database.windows.net \
  --name devin-sql-dns-link \
  --virtual-network VNET_NAME \
  --registration-enabled false

# Create DNS record group for the private endpoint
az network private-endpoint dns-zone-group create \
  --resource-group RESOURCE_GROUP \
  --endpoint-name devin-sql-pe \
  --name devin-sql-dns-group \
  --private-dns-zone privatelink.database.windows.net \
  --zone-name privatelink-database-windows-net
```

### 3. Disable Public Access (Recommended)

```bash
# Disable public network access -- all traffic flows through private endpoint
az sql server update \
  --resource-group RESOURCE_GROUP \
  --name SQL_SERVER_NAME \
  --public-network-access Disabled
```

### 4. Configure Network Access to Private Endpoint

**If using Zscaler ZPA:**
- Add the private endpoint's IP address as a ZPA Application Segment
- Protocol: TCP, Port: 1433
- Assign access policy consistent with existing Devin application segments

**If using ExpressRoute / VPN Gateway:**
- Ensure the private endpoint subnet is routable from the ExpressRoute or VPN Gateway
- Configure DNS forwarding so `SERVER.privatelink.database.windows.net` resolves to the private IP

### 5. Create the Database User

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

-- Grant execute on stored procedures if needed
GRANT EXECUTE ON SCHEMA::app_schema TO devin_dev;

-- Explicit deny on DDL operations
DENY CREATE TABLE TO devin_dev;
DENY ALTER ANY SCHEMA TO devin_dev;
```

## Devin Setup

### 1. Store Secrets

Add the following as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | Private endpoint hostname (Zscaler-reachable) | `server.privatelink.database.windows.net` |
| `DB_USER` | SQL auth username | `devin_dev` |
| `DB_PASSWORD` | SQL auth password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

No `initialize` or `maintenance` commands are needed -- Devin uses standard SQL client libraries to connect.

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Azure SQL) is available at $DB_HOST:1433.
      Connect with: sqlcmd -S $DB_HOST -d $DB_NAME -U $DB_USER -P $DB_PASSWORD
      Connection string: Server=tcp:$DB_HOST,1433;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;
```

### 3. MCP Server (Optional)

Enable the SQL Server MCP server in Settings > MCP Marketplace:
- Connection string: `Server=tcp:$DB_HOST,1433;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PASSWORD;Encrypt=true;TrustServerCertificate=false;`

This gives Devin natural-language database querying capabilities in addition to CLI and application access.

## Validation

```bash
# From a Devin session:
sqlcmd -S "$DB_HOST" -d "$DB_NAME" -U "$DB_USER" -P "$DB_PASSWORD"

# Verify read access
SELECT TOP 5 * FROM shared_schema.some_table;
GO

# Verify write access on app schema
INSERT INTO app_schema.test_table (col) VALUES ('test');
DELETE FROM app_schema.test_table WHERE col = 'test';
GO

# Verify DDL is denied (expected failure)
CREATE TABLE app_schema.bad_table (id INT);
GO
-- Msg 262: CREATE TABLE permission denied
```

## Security Properties

| Property | Status |
|---|---|
| Azure credentials on Devin | **None** |
| Secret rotation required | **DB password only** -- every 90 days or on personnel change |
| Transport encryption | TLS (always enforced by Azure SQL) + Zscaler/ExpressRoute |
| Blast radius if Devin secret leaks | Scoped DB user/password only -- no Azure AD access |
| Audit trail | Azure SQL audit logs show `devin_dev` queries; Zscaler logs show network access |
