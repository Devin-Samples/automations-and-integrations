# Option B: Service Account Key on Devin

> Fastest to stand up for POC. Cloud SQL Auth Proxy runs inside the Devin session, authenticated with a GCP service account key stored as a Devin secret.

## Overview

The customer generates a GCP service account key, provides it to the Devin org admin, and it is stored as a Devin org-scoped secret. Each Devin session starts Cloud SQL Auth Proxy using the key, providing a local `localhost:5432` PostgreSQL endpoint that the application and MCP server connect to.

The Auth Proxy handles mTLS encryption and (optionally) IAM-based database authentication, so no database password is needed if IAM DB auth is enabled.

## Prerequisites

- A GCP project with Cloud SQL PostgreSQL instance(s)
- Cloud SQL Admin API enabled in the project
- Network path from Devin to Cloud SQL (Zscaler or Devin static IPs in Authorized Networks)
- Devin org admin access to configure secrets and environment blueprints

## Customer Setup (GCP Side)

### 1. Create the Google Service Account

```bash
gcloud iam service-accounts create devin-db \
  --display-name="Devin Database Access" \
  --project=PROJECT_ID
```

### 2. Grant Cloud SQL Permissions

```bash
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:devin-db@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:devin-db@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.instanceUser"
```

### 3. Generate a Key

```bash
gcloud iam service-accounts keys create devin-sa-key.json \
  --iam-account=devin-db@PROJECT_ID.iam.gserviceaccount.com
```

Provide the contents of `devin-sa-key.json` to the Devin org admin via a secure channel. Delete the local copy after transfer.

### 4. Create the Database Role

**Option 1: IAM DB authentication (passwordless — recommended)**

```bash
# Enable IAM DB auth on the Cloud SQL instance
gcloud sql instances patch INSTANCE_NAME \
  --database-flags=cloudsql.iam_authentication=on
```

```sql
-- Create IAM-authenticated user
CREATE USER "devin-db@PROJECT_ID.iam" WITH LOGIN;

-- Grant schema-scoped permissions
GRANT USAGE ON SCHEMA app_schema TO "devin-db@PROJECT_ID.iam";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO "devin-db@PROJECT_ID.iam";
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO "devin-db@PROJECT_ID.iam";
```

**Option 2: Standard password authentication**

```sql
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';
-- Grant schema-scoped permissions (same as above, using devin_dev)
```

### 5. Configure Network Access

**Option A: Zscaler**
- Add Cloud SQL's public or private IP to ZIA/ZPA policy
- Allow TCP 5432 (as configured in the blueprint) through ZIA/ZPA policy

**Option B: Devin Static IPs**
```bash
gcloud sql instances patch INSTANCE_NAME \
  --authorized-networks="DEVIN_IP_1/32,DEVIN_IP_2/32,..."
```

Full IP list: https://docs.devin.ai/admin/common-issues#ip-whitelisting

## Devin Setup

### 1. Store Secrets

Add as **org-scoped** Devin Secrets (Settings > Secrets):

| Secret Name | Value | Notes |
|---|---|---|
| `GCP_SA_KEY` | Full JSON content of `devin-sa-key.json` | Multi-line JSON |
| `CLOUD_SQL_INSTANCE` | Instance connection name | Format: `project:region:instance` |
| `DB_NAME` | Database name | e.g., `dev_db` |
| `DB_USER` | (Only if using password auth) | e.g., `devin_dev` |
| `DB_PASSWORD` | (Only if using password auth) | |

### 2. Environment Blueprint

See [examples/blueprint-sa-key-proxy.yaml](../examples/blueprint-sa-key-proxy.yaml) for the full blueprint.

```yaml
initialize: |
  # Install Cloud SQL Auth Proxy (persists in snapshot)
  curl -o /usr/local/bin/cloud-sql-proxy \
    https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.2/cloud-sql-proxy.linux.amd64
  chmod +x /usr/local/bin/cloud-sql-proxy

maintenance: |
  # Write SA key to tmpfs (RAM-backed, never persists to disk or snapshots).
  # /dev/shm is always tmpfs on Linux — unlike /tmp, it is never captured in
  # VM snapshots. Devin strips secret env vars before snapshot save, but files
  # written to disk-backed paths would persist.
  printf '%s\n' "$GCP_SA_KEY" > /dev/shm/gcp-sa-key.json
  chmod 600 /dev/shm/gcp-sa-key.json
  # Start Cloud SQL Auth Proxy
  cloud-sql-proxy "$CLOUD_SQL_INSTANCE" \
    --credentials-file=/dev/shm/gcp-sa-key.json \
    --port 5432 &
  sleep 3

knowledge:
  - name: database
    contents: |
      Cloud SQL dev DB is available at localhost:5432 via Auth Proxy.
      Connect with: psql -h localhost -p 5432 -U devin_dev -d $DB_NAME
      Or use DATABASE_URL=postgresql://devin_dev@localhost:5432/$DB_NAME
```

### 3. MCP Server (Optional)

Enable the PostgreSQL MCP server in Settings > MCP Marketplace:

- **With IAM DB auth:** `postgresql://devin-db%40PROJECT_ID.iam@localhost:5432/DB_NAME` (no password)
- **With password auth:** `postgresql://devin_dev:PASSWORD@localhost:5432/DB_NAME`

## Validation

```bash
# From a Devin session:

# Check proxy is running
ps aux | grep cloud-sql-proxy

# Connect (IAM DB auth — no password prompt)
psql -h localhost -p 5432 -d $DB_NAME

# Connect (password auth)
psql -h localhost -p 5432 -U devin_dev -d $DB_NAME

# Test queries (same as Option A)
```

## Key Rotation

SA keys should be rotated every 90 days:

1. Generate a new key:
   ```bash
   gcloud iam service-accounts keys create new-key.json \
     --iam-account=devin-db@PROJECT_ID.iam.gserviceaccount.com
   ```
2. Update the `GCP_SA_KEY` Devin Secret with the new key contents
3. Delete the old key:
   ```bash
   gcloud iam service-accounts keys delete OLD_KEY_ID \
     --iam-account=devin-db@PROJECT_ID.iam.gserviceaccount.com
   ```

## Security Properties

| Property | Status |
|---|---|
| GCP credentials on Devin | SA key JSON in Devin Secrets (encrypted, stripped from snapshots) |
| Key rotation required | **Yes** — every 90 days |
| Transport encryption | mTLS via Cloud SQL Auth Proxy |
| Blast radius if Devin secret leaks | `cloudsql.client` + `cloudsql.instanceUser` on one project |
| Audit trail | SA key ID in GCP Cloud Audit Logs |
