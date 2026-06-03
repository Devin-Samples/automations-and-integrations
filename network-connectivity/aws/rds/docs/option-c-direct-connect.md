# Option C: Direct Connect

> Simplest possible setup. Devin connects directly to RDS using a standard PostgreSQL connection string — no proxy, no AWS identity.

## Overview

Devin connects to RDS PostgreSQL using a standard `postgresql://` connection string over TLS. No RDS Proxy, no IAM credentials, no special binaries. The only credential on Devin is a database user and password.

This is the fastest path to a working connection but provides fewer security layers than Options A or B.

## Prerequisites

- An RDS PostgreSQL instance with **public accessibility** enabled (or reachable via Zscaler ZPA)
- TLS enforcement enabled on the RDS instance (default for RDS)
- Network path from Devin to the RDS endpoint
- Devin org admin access to configure secrets

## Customer Setup (AWS Side)

### 1. Enable Public Accessibility

```bash
# Ensure the instance has public accessibility enabled
aws rds describe-db-instances \
  --db-instance-identifier your-rds-instance \
  --query 'DBInstances[0].PubliclyAccessible'

# If not, enable it (requires instance modification)
aws rds modify-db-instance \
  --db-instance-identifier your-rds-instance \
  --publicly-accessible \
  --apply-immediately
```

> **Note:** The RDS instance must be in a subnet with an Internet Gateway route for public accessibility to work. Alternatively, route traffic through Zscaler ZPA to avoid exposing the instance publicly.

### 2. Configure Security Group

**Option A: Devin Static IPs**
```bash
# Get the Security Group ID for the RDS instance
SG_ID=$(aws rds describe-db-instances \
  --db-instance-identifier your-rds-instance \
  --query 'DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Add Devin's static egress IPs
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr DEVIN_IP_1/32

# Repeat for each Devin egress IP
```

Full IP list: https://docs.devin.ai/admin/common-issues#ip-whitelisting

**Option B: Zscaler ZPA**
- Add the RDS instance endpoint as a ZPA Application Segment (TCP 5432)

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

### 4. Enforce TLS

RDS PostgreSQL supports TLS by default, but does not require it unless configured. To enforce TLS for all connections:

```bash
# Set rds.force_ssl = 1 in the DB parameter group
aws rds modify-db-parameter-group \
  --db-parameter-group-name your-parameter-group \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=pending-reboot"
```

> **Note:** Per-role SSL enforcement is not possible in PostgreSQL/RDS — `ssl` is a server-level parameter. Use `rds.force_ssl` for server-wide enforcement, and always specify `sslmode=require` in client connection strings.

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | RDS instance endpoint | `your-instance.xxxx.REGION.rds.amazonaws.com` |
| `DB_USER` | PostgreSQL username | `devin_dev` |
| `DB_PASSWORD` | PostgreSQL password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

See [examples/blueprint-direct-connect.yaml](../examples/blueprint-direct-connect.yaml).

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (RDS PostgreSQL) is at $DB_HOST:5432.
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
| AWS credentials on Devin | **None** — DB password only |
| Key rotation required | **No** — no AWS key. DB password should be rotated every 90 days |
| Transport encryption | RDS TLS (not mTLS) |
| Blast radius if Devin secret leaks | Scoped DB user/password — limited to granted schemas |
| Audit trail | RDS audit logs show `devin_dev` queries |

## When to Choose This Option

- You want the absolute fastest path to a working connection
- The database can be made publicly accessible and you're comfortable with Security Group allowlisting
- IAM DB authentication is not required by your security policy
- You want to avoid installing additional binaries in the Devin environment

## When to Upgrade to Option A or B

Consider upgrading if:
- You need to eliminate the RDS public endpoint
- Your security policy requires IAM-based authentication (not just DB passwords)
- You want connection pooling (RDS Proxy provides this natively)
- You're moving from POC to production
