# Option A: Customer-Hosted Proxy

> Keep all GCP identity on the customer side. Devin holds only a scoped database password.

## Overview

The customer deploys Cloud SQL Auth Proxy on their own GCP infrastructure (a GCE VM, Cloud Run service, or GKE pod) with the Google Service Account (GSA) attached natively as an instance service account — no key file is ever generated. Devin reaches the proxied PostgreSQL endpoint through the existing network path (typically Zscaler ZPA) and authenticates with a standard database user and password.

This mirrors how human developers typically access the database: through a corporate zero-trust network to a database endpoint, authenticating with DB credentials, without holding GCP service account keys on their machines.

## Prerequisites

- A GCP project with Cloud SQL PostgreSQL instance(s)
- Cloud SQL Admin API enabled in the project
- A network path from Devin to the customer's GCP environment (Zscaler ZPA recommended)
- Devin org admin access to configure secrets

## Customer Setup (GCP Side)

### 1. Create the Google Service Account

```bash
gcloud iam service-accounts create devin-db \
  --display-name="Devin Database Access" \
  --project=PROJECT_ID
```

### 2. Grant Cloud SQL Permissions

```bash
# Allow connecting via Cloud SQL Auth Proxy
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:devin-db@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.client"

# (Optional) Allow IAM DB authentication
gcloud projects add-iam-policy-binding PROJECT_ID \
  --member="serviceAccount:devin-db@PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/cloudsql.instanceUser"
```

### 3. Deploy the Proxy VM

**Option: GCE VM**

```bash
# Create a small VM with the GSA as its service account
gcloud compute instances create devin-db-proxy \
  --project=PROJECT_ID \
  --zone=ZONE \
  --machine-type=e2-micro \
  --service-account=devin-db@PROJECT_ID.iam.gserviceaccount.com \
  --scopes=https://www.googleapis.com/auth/cloud-platform \
  --metadata=startup-script='#!/bin/bash
    curl -o /usr/local/bin/cloud-sql-proxy \
      https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.2/cloud-sql-proxy.linux.amd64
    chmod +x /usr/local/bin/cloud-sql-proxy
    cloud-sql-proxy PROJECT_ID:REGION:INSTANCE_NAME \
      --address 0.0.0.0 --port 5432 &'
```

**Option: Cloud Run**

Cloud SQL Auth Proxy is built into Cloud Run via [Cloud SQL connections](https://cloud.google.com/sql/docs/postgres/connect-run). Deploy a lightweight TCP proxy service that exposes port 5432 backed by the Cloud SQL connection.

### 4. Configure Network Access

**If using Zscaler ZPA:**
- Add the proxy VM's internal IP as a ZPA Application Segment
- Protocol: TCP, Port: 5432
- Assign access policy consistent with existing Devin application segments

**If using direct access:**
- Open firewall rule for TCP/5432 from Devin's [static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to the proxy VM

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
| `DB_HOST` | Proxy VM hostname or IP (Zscaler-reachable) | `devin-db-proxy.internal.example.com` |
| `DB_USER` | PostgreSQL username | `devin_dev` |
| `DB_PASSWORD` | PostgreSQL password | (secure password) |
| `DB_NAME` | Database name | `dev_db` |

### 2. Environment Blueprint

No `initialize` or `maintenance` commands are needed — Devin just uses standard PostgreSQL client libraries to connect.

```yaml
knowledge:
  - name: database
    contents: |
      Dev database (Cloud SQL PostgreSQL) is available at $DB_HOST:5432.
      Connect with: psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME"
      Or set DATABASE_URL=postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME for the app's connection config.
```

### 3. MCP Server (Optional)

Enable the PostgreSQL MCP server in Settings > MCP Marketplace:
- Connection string: `postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME`

This gives Devin natural-language database querying capabilities in addition to CLI and application access.

## Validation

```bash
# From a Devin session:
psql "postgresql://$DB_USER:$DB_PASSWORD@$DB_HOST:5432/$DB_NAME"

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
| GCP credentials on Devin | **None** |
| Key rotation required | **No** — no key exists |
| Transport encryption | mTLS (Auth Proxy) + Zscaler |
| Blast radius if Devin secret leaks | Scoped DB user/password only — no GCP IAM access |
| Audit trail | Cloud SQL audit logs show `devin_dev` queries; Zscaler logs show network access |
