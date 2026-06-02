# Option B: IAM Credentials on Devin

> Fastest to stand up for POC. An AWS IAM user access key stored as a Devin secret enables IAM DB authentication with short-lived tokens — or simple password auth with IAM-only for RDS API access.

## Overview

The customer creates a scoped IAM user, generates an access key, and provides it to the Devin org admin. The key is stored as a Devin org-scoped secret. Each Devin session uses the AWS CLI to generate short-lived IAM DB auth tokens (15-minute lifetime) that replace the need for a stored database password.

Alternatively, the IAM user can be used only for RDS API access (e.g., `rds:DescribeDBInstances`) while database authentication uses a standard password.

## Prerequisites

- An AWS account with RDS PostgreSQL instance(s)
- IAM DB authentication enabled on the RDS instance (for IAM DB auth flow)
- Network path from Devin to the RDS endpoint (internet access for public instances; Zscaler ZPA for private instances)
- Devin org admin access to configure secrets and environment blueprints

## Customer Setup (AWS Side)

### 1. Create the IAM User

```bash
aws iam create-user --user-name devin-db-user
```

### 2. Create the IAM Policy

```bash
cat > devin-rds-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rds-db:connect",
      "Resource": "arn:aws:rds-db:REGION:ACCOUNT_ID:dbuser:DBI_RESOURCE_ID/devin_iam"
    },
    {
      "Effect": "Allow",
      "Action": "rds:DescribeDBInstances",
      "Resource": "arn:aws:rds:REGION:ACCOUNT_ID:db:your-rds-instance"
    }
  ]
}
EOF

aws iam create-policy \
  --policy-name DevinRDSAccess \
  --policy-document file://devin-rds-policy.json

aws iam attach-user-policy \
  --user-name devin-db-user \
  --policy-arn arn:aws:iam::ACCOUNT_ID:policy/DevinRDSAccess
```

> **Note:** The `rds-db:connect` resource ARN uses the **DBI Resource ID** (starts with `dbi-`), not the instance name. Find it with:
> ```bash
> aws rds describe-db-instances --db-instance-identifier your-rds-instance \
>   --query 'DBInstances[0].DbiResourceId' --output text
> ```

### 3. Generate an Access Key

```bash
aws iam create-access-key --user-name devin-db-user
```

Provide the `AccessKeyId` and `SecretAccessKey` to the Devin org admin via a secure channel. Delete the local copy after transfer.

### 4. Create the Database Role

**Option 1: IAM DB authentication (recommended)**

```bash
# Enable IAM DB auth on the RDS instance
aws rds modify-db-instance \
  --db-instance-identifier your-rds-instance \
  --enable-iam-database-authentication \
  --apply-immediately
```

```sql
-- Create IAM-authenticated user (must match the IAM policy resource)
CREATE USER devin_iam WITH LOGIN;
GRANT rds_iam TO devin_iam;

-- Grant schema-scoped permissions
GRANT USAGE ON SCHEMA app_schema TO devin_iam;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO devin_iam;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO devin_iam;
```

**Option 2: Standard password authentication**

```sql
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';
-- Grant schema-scoped permissions (same as above, using devin_dev)
```

### 5. Configure Network Access

For IAM DB authentication, Devin must be able to reach the RDS endpoint:

- **Public instance:** Add Devin's [static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to the RDS Security Group for TCP/5432
- **Private instance:** Use **Zscaler ZPA** to route traffic to the VPC, or pair with [SSM Port Forwarding](../../ssm-port-forwarding/) to reach a bastion that has VPC access

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Notes |
|---|---|---|
| `DEVIN_AWS_ACCESS_KEY_ID` | IAM user access key ID | From `create-access-key` output |
| `DEVIN_AWS_SECRET_ACCESS_KEY` | IAM user secret access key | From `create-access-key` output |
| `RDS_ENDPOINT` | RDS instance endpoint | e.g., `your-instance.xxxx.REGION.rds.amazonaws.com` |
| `RDS_PORT` | RDS port | `5432` |
| `DB_NAME` | Database name | e.g., `dev_db` |
| `DB_USER` | PostgreSQL username | `devin_iam` (IAM auth) or `devin_dev` (password auth) |
| `DB_PASSWORD` | (Only if using password auth) | |

### 2. Environment Blueprint

See [examples/blueprint-iam-auth.yaml](../examples/blueprint-iam-auth.yaml) for the full blueprint.

```yaml
initialize: |
  # Install AWS CLI v2 (persists in snapshot)
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -qo /tmp/awscliv2.zip -d /tmp/aws-install
  /tmp/aws-install/aws/install --update
  rm -rf /tmp/awscliv2.zip /tmp/aws-install

maintenance: |
  # Write AWS credentials to tmpfs (RAM-backed, never persists to disk or snapshots).
  # /dev/shm is always tmpfs on Linux — unlike /tmp, it is never captured in
  # VM snapshots. Devin strips secret env vars before snapshot save, but files
  # written to disk-backed paths would persist.
  mkdir -p /dev/shm/.aws
  printf '%s\n' "[default]" \
    "aws_access_key_id = $DEVIN_AWS_ACCESS_KEY_ID" \
    "aws_secret_access_key = $DEVIN_AWS_SECRET_ACCESS_KEY" \
    "region = $AWS_DEFAULT_REGION" > /dev/shm/.aws/credentials
  chmod 600 /dev/shm/.aws/credentials
  export AWS_SHARED_CREDENTIALS_FILE=/dev/shm/.aws/credentials

knowledge:
  - name: database
    contents: |
      RDS PostgreSQL dev DB is available at $RDS_ENDPOINT:$RDS_PORT.
      IAM DB auth — generate a fresh token:
        export PGPASSWORD=$(aws rds generate-db-auth-token --hostname $RDS_ENDPOINT --port $RDS_PORT --username $DB_USER --region $AWS_DEFAULT_REGION)
        psql "host=$RDS_ENDPOINT port=$RDS_PORT user=$DB_USER dbname=$DB_NAME sslmode=require"
      Password auth:
        psql "postgresql://$DB_USER:$DB_PASSWORD@$RDS_ENDPOINT:$RDS_PORT/$DB_NAME?sslmode=require"
      Set AWS_SHARED_CREDENTIALS_FILE=/dev/shm/.aws/credentials if aws CLI cannot find credentials.
```

### 3. MCP Server (Optional)

Enable the PostgreSQL MCP server in Settings > MCP Marketplace:

- **With IAM DB auth:** Generate the token first, then use `postgresql://devin_iam:TOKEN@RDS_ENDPOINT:5432/DB_NAME?sslmode=require` (token is short-lived — MCP may need a wrapper script to refresh)
- **With password auth:** `postgresql://devin_dev:PASSWORD@RDS_ENDPOINT:5432/DB_NAME?sslmode=require`

## Validation

```bash
# From a Devin session:

# Check AWS CLI is available
aws --version

# Generate an IAM DB auth token
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname $RDS_ENDPOINT \
  --port $RDS_PORT \
  --username $DB_USER \
  --region $AWS_DEFAULT_REGION)

# Connect with IAM auth
psql "host=$RDS_ENDPOINT port=$RDS_PORT user=$DB_USER dbname=$DB_NAME sslmode=require"

# Or connect with password auth
psql "postgresql://$DB_USER:$DB_PASSWORD@$RDS_ENDPOINT:$RDS_PORT/$DB_NAME?sslmode=require"

# Test queries (same as Option A)
```

## Key Rotation

IAM access keys should be rotated every 90 days:

1. Generate a new access key:
   ```bash
   aws iam create-access-key --user-name devin-db-user
   ```
2. Update `DEVIN_AWS_ACCESS_KEY_ID` and `DEVIN_AWS_SECRET_ACCESS_KEY` in Devin Secrets
3. Delete the old access key:
   ```bash
   aws iam delete-access-key --user-name devin-db-user --access-key-id OLD_KEY_ID
   ```

## Security Properties

| Property | Status |
|---|---|
| AWS credentials on Devin | IAM user access key in Devin Secrets (encrypted, stripped from snapshots) |
| Key rotation required | **Yes** — every 90 days |
| Transport encryption | TLS (RDS enforced) |
| Blast radius if Devin secret leaks | `rds-db:connect` + `rds:DescribeDBInstances` on one instance |
| Audit trail | IAM access key ID in AWS CloudTrail; DB user in RDS audit logs |
