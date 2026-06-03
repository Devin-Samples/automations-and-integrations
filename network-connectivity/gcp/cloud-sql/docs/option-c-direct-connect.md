# Option C: Direct Connect

> Simplest possible setup. Devin connects directly to Cloud SQL using a standard PostgreSQL connection string — no proxy, no GCP identity.

## Overview

Devin connects to Cloud SQL PostgreSQL using a standard `postgresql://` connection string over TLS. No Cloud SQL Auth Proxy, no GCP service account, no special binaries. The only credential on Devin is a database user and password.

This is the fastest path to a working connection but provides fewer security layers than Options A or B.

## Prerequisites

- A Cloud SQL PostgreSQL instance with a **public IP** (or reachable via a private network path such as IAP tunneling, Zscaler ZPA, or VPN)
- SSL/TLS enforcement enabled on the Cloud SQL instance
- Network path from Devin to the Cloud SQL endpoint
- Devin org admin access to configure secrets

## Customer Setup (GCP Side)

### 1. Enable Public IP and SSL

```bash
# Ensure the instance has a public IP
gcloud sql instances describe INSTANCE_NAME --format="get(ipAddresses)"

# Require SSL for all connections
gcloud sql instances patch INSTANCE_NAME --require-ssl
```

### 2. Configure Authorized Networks

**Option A: Devin Static IPs**
```bash
gcloud sql instances patch INSTANCE_NAME \
  --authorized-networks="DEVIN_IP_1/32,DEVIN_IP_2/32,..."
```

Full IP list: https://docs.devin.ai/admin/common-issues#ip-whitelisting

**Option B: Private network path (IAP, Zscaler ZPA, VPN, etc.)**
- **IAP Tunneling:** See [IAP Tunneling](../../iap-tunneling/) — no public IP needed
- **Zscaler ZPA:** Add the Cloud SQL public IP as a ZPA Application Segment (TCP 5432)
- **VPN:** Configure Cloud VPN with routing to the Cloud SQL network — see [Devin VPN docs](https://docs.devin.ai/onboard-devin/vpn)

### 3. Create the Database Role

```sql
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

### 4. Download SSL Certificates (Optional)

For client-side certificate verification:

```bash
# Download the server CA cert
gcloud sql instances describe INSTANCE_NAME \
  --format="get(serverCaCert.cert)" > server-ca.pem
```

Provide `server-ca.pem` to the Devin org admin if client-side CA verification is required.

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | Cloud SQL public IP or hostname reachable via your network path | `34.123.45.67` |
| `DB_USER` | PostgreSQL username | `devin_dev` |
| `DB_PASSWORD` | PostgreSQL password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-direct-connect.yaml](../examples/blueprint-direct-connect.yaml).

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Cloud SQL PostgreSQL) is at $DB_HOST:5432.
      Connect with: psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME?sslmode=require"
      Or set DATABASE_URL for the app's connection config.
```

No `initialize` or `maintenance` commands needed — `psql` and standard PostgreSQL client libraries (libpq) are already available in Devin sessions.

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
| GCP credentials on Devin | **None** — DB password only |
| Key rotation required | **No** — no GCP key. DB password should be rotated every 90 days |
| Transport encryption | Cloud SQL SSL/TLS (not mTLS) |
| Blast radius if Devin secret leaks | Scoped DB user/password — limited to granted schemas |
| Audit trail | Cloud SQL audit logs show `devin_dev` queries |

## When to Choose This Option

- You want the absolute fastest path to a working connection
- The database has a public IP and you're comfortable with IP allowlisting
- mTLS (via Auth Proxy) is not required by your security policy
- You want to avoid installing additional binaries in the Devin environment

## When to Upgrade to Option A or B

Consider upgrading if:
- You need mTLS encryption (not just TLS)
- You want to eliminate the Cloud SQL public IP
- Your security policy requires GCP IAM-based authentication (not just DB passwords)
- You're moving from POC to production
