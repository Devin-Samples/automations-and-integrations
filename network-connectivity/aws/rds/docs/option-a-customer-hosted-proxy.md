# Option A: Customer-Hosted Proxy

> Keep all AWS identity on the customer side. Devin holds only a scoped database password.

## Overview

The customer deploys an RDS Proxy (AWS managed) or pgbouncer on EC2 with an IAM role attached natively — no access key is ever generated. Devin reaches the proxied PostgreSQL endpoint through the existing network path (typically Zscaler ZPA) and authenticates with a standard database user and password.

This mirrors how human developers typically access the database: through a corporate zero-trust network to a database endpoint, authenticating with DB credentials, without holding AWS access keys on their machines.

## Prerequisites

- An AWS account with RDS PostgreSQL instance(s)
- A network path from Devin to the customer's AWS environment (Zscaler ZPA recommended)
- Devin org admin access to configure secrets

## Customer Setup (AWS Side)

### 1. Create the IAM Role for the Proxy

```bash
# Create a trust policy for RDS Proxy
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

aws iam create-role \
  --role-name devin-rds-proxy-role \
  --assume-role-policy-document file://trust-policy.json
```

### 2. Grant Secrets Manager Access (for RDS Proxy)

RDS Proxy retrieves database credentials from AWS Secrets Manager:

```bash
# Store the DB password in Secrets Manager
aws secretsmanager create-secret \
  --name devin-db-credentials \
  --secret-string '{"username":"devin_dev","password":"SECURE_PASSWORD"}'

# Grant the proxy role access to the secret
cat > secrets-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:REGION:ACCOUNT_ID:secret:devin-db-credentials-*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name devin-rds-proxy-role \
  --policy-name SecretsAccess \
  --policy-document file://secrets-policy.json
```

### 3a. Deploy RDS Proxy (Managed — Recommended)

```bash
aws rds create-db-proxy \
  --db-proxy-name devin-rds-proxy \
  --engine-family POSTGRESQL \
  --auth '[{
    "AuthScheme": "SECRETS",
    "SecretArn": "arn:aws:secretsmanager:REGION:ACCOUNT_ID:secret:devin-db-credentials-XXXXXX",
    "IAMAuth": "DISABLED"
  }]' \
  --role-arn arn:aws:iam::ACCOUNT_ID:role/devin-rds-proxy-role \
  --vpc-subnet-ids subnet-xxxx subnet-yyyy \
  --vpc-security-group-ids sg-xxxx

# Register the target RDS instance
aws rds register-db-proxy-targets \
  --db-proxy-name devin-rds-proxy \
  --db-instance-identifiers your-rds-instance
```

### 3b. Deploy pgbouncer on EC2 (Alternative)

```bash
# Launch an EC2 instance with the IAM role
aws ec2 run-instances \
  --image-id ami-xxxxxxxxx \
  --instance-type t3.micro \
  --iam-instance-profile Name=devin-rds-proxy-profile \
  --subnet-id subnet-xxxx \
  --security-group-ids sg-xxxx \
  --user-data '#!/bin/bash
    apt-get update && apt-get install -y pgbouncer
    cat > /etc/pgbouncer/pgbouncer.ini << CONF
[databases]
dev_db = host=your-rds-endpoint.REGION.rds.amazonaws.com port=5432 dbname=dev_db
[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 5432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt
pool_mode = transaction
CONF
    echo "\"devin_dev\" \"SECURE_PASSWORD\"" > /etc/pgbouncer/userlist.txt
    systemctl enable pgbouncer && systemctl start pgbouncer'
```

### 4. Configure Network Access

**If using Zscaler ZPA:**
- Add the RDS Proxy endpoint (or EC2 proxy internal IP) as a ZPA Application Segment
- Protocol: TCP, Port: 5432
- Assign access policy consistent with existing Devin application segments

**If using direct access:**
- Open Security Group for TCP/5432 from Devin's [static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to the proxy

### 5. Create the Database Role

```sql
-- Create a dedicated user for Devin
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';

-- Grant schema-scoped permissions
GRANT CONNECT ON DATABASE dev_db TO devin_dev;

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

## Devin Setup

### 1. Store Secrets

Add the following as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Example |
|---|---|---|
| `DB_HOST` | RDS Proxy endpoint or EC2 proxy hostname (Zscaler-reachable) | `devin-rds-proxy.proxy-xxxx.REGION.rds.amazonaws.com` |
| `DB_USER` | PostgreSQL username | `devin_dev` |
| `DB_PASSWORD` | PostgreSQL password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

No `initialize` or `maintenance` commands are needed — Devin just uses standard PostgreSQL client libraries to connect.

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (RDS PostgreSQL) is available at $DB_HOST:5432.
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
| AWS credentials on Devin | **None** |
| Key rotation required | **No** — no access key exists |
| Transport encryption | TLS (RDS enforced) + Zscaler |
| Blast radius if Devin secret leaks | Scoped DB user/password only — no AWS IAM access |
| Audit trail | RDS audit logs show `devin_dev` queries; Zscaler logs show network access |
