# Option C2: Customer-Hosted Private Endpoint — Azure Database for PostgreSQL

> Keep all Azure identity on the customer side. Devin holds only a scoped database password.

## Overview

The customer creates an Azure Private Endpoint for their Azure Database for PostgreSQL Flexible Server (or uses VNet integration), making it reachable via a private IP within their VNet. Devin reaches this private endpoint through the existing network path (typically Zscaler ZPA or VPN Gateway) and authenticates with a standard PostgreSQL user and password.

This mirrors how human developers typically access the database: through a corporate zero-trust network to a database endpoint, authenticating with DB credentials, without holding Azure service principal secrets on their machines.

## Prerequisites

- An Azure subscription with an Azure Database for PostgreSQL Flexible Server
- A VNet with a subnet available for the private endpoint (or VNet-integrated Flexible Server)
- A network path from Devin to the customer's Azure VNet (Zscaler ZPA recommended)
- Devin org admin access to configure secrets

## Customer Setup (Azure Side)

### 1. Create the Private Endpoint

```bash
# Get the Flexible Server resource ID
PG_RESOURCE_ID=$(az postgres flexible-server show \
  --resource-group RESOURCE_GROUP \
  --name PG_SERVER_NAME \
  --query id -o tsv)

# Create a private endpoint for the Flexible Server in an existing subnet
az network private-endpoint create \
  --resource-group RESOURCE_GROUP \
  --name devin-pg-pe \
  --vnet-name VNET_NAME \
  --subnet SUBNET_NAME \
  --private-connection-resource-id "$PG_RESOURCE_ID" \
  --group-id postgresqlServer \
  --connection-name devin-pg-connection
```

### 2. Configure Private DNS (Recommended)

```bash
# Create private DNS zone for Azure PostgreSQL
az network private-dns zone create \
  --resource-group RESOURCE_GROUP \
  --name privatelink.postgres.database.azure.com

# Link DNS zone to VNet
az network private-dns zone-link vnet create \
  --resource-group RESOURCE_GROUP \
  --zone-name privatelink.postgres.database.azure.com \
  --name devin-pg-dns-link \
  --virtual-network VNET_NAME \
  --registration-enabled false

# Create DNS record group for the private endpoint
az network private-endpoint dns-zone-group create \
  --resource-group RESOURCE_GROUP \
  --endpoint-name devin-pg-pe \
  --name devin-pg-dns-group \
  --private-dns-zone privatelink.postgres.database.azure.com \
  --zone-name privatelink-postgres-database-azure-com
```

### 3. Disable Public Access (Recommended)

```bash
az postgres flexible-server update \
  --resource-group RESOURCE_GROUP \
  --name PG_SERVER_NAME \
  --public-access Disabled
```

### 4. Configure Network Access to Private Endpoint

**If using Zscaler ZPA:**
- Add the private endpoint's IP address as a ZPA Application Segment
- Protocol: TCP, Port: 5432
- Assign access policy consistent with existing Devin application segments

**If using VPN Gateway:**
- Ensure the private endpoint subnet is routable from the VPN Gateway
- Configure DNS forwarding so `SERVER.privatelink.postgres.database.azure.com` resolves to the private IP

### 5. Create the Database Role

```sql
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';

GRANT CONNECT ON DATABASE dev_db TO devin_dev;

GRANT USAGE ON SCHEMA shared_schema TO devin_dev;
GRANT SELECT ON ALL TABLES IN SCHEMA shared_schema TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA shared_schema
  GRANT SELECT ON TABLES TO devin_dev;

GRANT USAGE ON SCHEMA app_schema TO devin_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO devin_dev;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app_schema TO devin_dev;
```

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | Private endpoint hostname (Zscaler-reachable) | `server.privatelink.postgres.database.azure.com` |
| `DB_USER` | PostgreSQL username | `devin_dev` |
| `DB_PASSWORD` | PostgreSQL password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

No `initialize` or `maintenance` commands are needed -- Devin uses standard PostgreSQL client libraries to connect.

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Azure PostgreSQL Flexible Server) is available at $DB_HOST:5432.
      Connect with: psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require"
      Or set DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require for the app's connection config.
```

### 3. MCP Server (Optional)

Enable the PostgreSQL MCP server in Settings > MCP Marketplace:
- Connection string: `postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require`

This gives Devin natural-language database querying capabilities in addition to CLI and application access.

## Validation

```bash
# From a Devin session:
psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require"

# Verify TLS is active
SELECT ssl_is_used();
-- Should return 't'

# Verify read access
SELECT * FROM shared_schema.some_table LIMIT 5;

# Verify write access on app schema
INSERT INTO app_schema.test_table (col) VALUES ('test');
DELETE FROM app_schema.test_table WHERE col = 'test';

# Verify DDL is denied (expected failure)
DROP TABLE app_schema.test_table;
-- ERROR: permission denied
```

## Security Properties

| Property | Status |
|---|---|
| Azure credentials on Devin | **None** |
| Secret rotation required | **DB password only** -- every 90 days or on personnel change |
| Transport encryption | TLS (enforced by Flexible Server) + Zscaler/VPN Gateway encryption |
| Blast radius if Devin secret leaks | Scoped DB user/password only -- no Azure AD access |
| Audit trail | Azure PostgreSQL audit logs show `devin_dev` queries; Zscaler logs show network access |
