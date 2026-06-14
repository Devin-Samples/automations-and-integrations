# Option C: Direct Connect

> Simplest possible setup. Devin connects directly to Azure Database for PostgreSQL using a standard connection string -- no service principal, no Azure identity.

## Overview

Devin connects to Azure Database for PostgreSQL Flexible Server using a standard `postgresql://` connection string over TLS. No Azure CLI, no service principal, no special binaries. The only credential on Devin is a database user and password.

Azure Database for PostgreSQL Flexible Server **enforces TLS by default** (`require_secure_transport = ON`). Even with this simplest option, transport encryption is guaranteed unless the customer has explicitly disabled it.

This is the fastest path to a working connection but provides fewer security layers than Options A or B.

## Prerequisites

- An Azure Database for PostgreSQL Flexible Server with **public access enabled** (or reachable via Zscaler ZPA)
- Network path from Devin to the Flexible Server endpoint
- Devin org admin access to configure secrets

## Customer Setup (Azure Side)

### 1. Enable Public Network Access

Verify that the Flexible Server allows public network access:

```bash
az postgres flexible-server show \
  --resource-group RESOURCE_GROUP \
  --name PG_SERVER_NAME \
  --query network.publicNetworkAccess -o tsv
# Should return "Enabled"
```

If disabled, enable it:

```bash
az postgres flexible-server update \
  --resource-group RESOURCE_GROUP \
  --name PG_SERVER_NAME \
  --public-access Enabled
```

### 2. Configure Firewall Rules

**Option A: Devin Static IPs**

```bash
# Add Devin's static egress IPs to the server firewall
# Full IP list: https://docs.devin.ai/admin/common-issues#ip-whitelisting
az postgres flexible-server firewall-rule create \
  --resource-group RESOURCE_GROUP \
  --name PG_SERVER_NAME \
  --rule-name devin-egress-1 \
  --start-ip-address DEVIN_IP_1 \
  --end-ip-address DEVIN_IP_1

# Repeat for each Devin egress IP
```

**Option B: Zscaler ZPA**
- Add the Flexible Server's public endpoint (`SERVER.postgres.database.azure.com:5432`) as a ZPA Application Segment

### 3. Create the Database Role

```sql
-- Create a dedicated user for Devin
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';

-- Read-only on shared schemas
GRANT USAGE ON SCHEMA shared_schema TO devin_dev;
GRANT SELECT ON ALL TABLES IN SCHEMA shared_schema TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA shared_schema
  GRANT SELECT ON TABLES TO devin_dev;

-- Read-write on application schema
GRANT USAGE ON SCHEMA app_schema TO devin_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO devin_dev;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app_schema TO devin_dev;
```

### 4. Verify TLS Enforcement (Optional)

```bash
# Check that require_secure_transport is ON (default)
az postgres flexible-server parameter show \
  --resource-group RESOURCE_GROUP \
  --server-name PG_SERVER_NAME \
  --name require_secure_transport \
  --query value -o tsv
# Should return "on"
```

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | Flexible Server public hostname | `server.postgres.database.azure.com` |
| `DB_USER` | PostgreSQL username | `devin_dev` |
| `DB_PASSWORD` | PostgreSQL password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-direct-connect.yaml](../examples/blueprint-direct-connect.yaml).

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Azure PostgreSQL Flexible Server) is at $DB_HOST:5432.
      Connect with: psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require"
      Or set DATABASE_URL for the app's connection config.
      TLS is enforced by default on Azure PostgreSQL Flexible Server.
```

No `initialize` or `maintenance` commands needed -- `psql` and standard PostgreSQL client libraries (libpq) are already available in Devin sessions.

### 3. MCP Server (Optional)

Enable the PostgreSQL MCP server in Settings > MCP Marketplace:
- Connection string: `postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require`

## Validation

```bash
# From a Devin session:
psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require"

# Verify TLS is active
SELECT ssl_is_used();
-- Should return 't'

# Test read access
SELECT * FROM shared_schema.some_table LIMIT 5;

# Test write access
INSERT INTO app_schema.test_table (col) VALUES ('test');
DELETE FROM app_schema.test_table WHERE col = 'test';
```

## Security Properties

| Property | Status |
|---|---|
| Azure credentials on Devin | **None** -- DB password only |
| Secret rotation required | **No Azure key** -- DB password should be rotated every 90 days |
| Transport encryption | TLS (enforced by default on Flexible Server -- `require_secure_transport = ON`) |
| Blast radius if Devin secret leaks | Scoped DB user/password -- limited to granted schemas |
| Audit trail | Azure PostgreSQL audit logs show `devin_dev` queries |

## When to Choose This Option

- You want the absolute fastest path to a working connection
- The database has a public endpoint and you're comfortable with IP allowlisting
- Entra ID token-based authentication is not required by your security policy
- You want to avoid installing additional tools (Azure CLI) in the Devin environment

## When to Upgrade to Option A or B

Consider upgrading if:
- You need to disable the Flexible Server's public endpoint
- Your security policy requires Entra ID token-based authentication (not just DB passwords)
- You want short-lived tokens instead of long-lived passwords
- You're moving from POC to production
