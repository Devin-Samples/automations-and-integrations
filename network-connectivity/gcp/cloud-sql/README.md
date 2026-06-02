# GCP Cloud SQL Connectivity

Connect Devin to GCP Cloud SQL PostgreSQL databases — customer-hosted proxy, service account key, and direct connect options with Zscaler ZPA integration.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Devin Session (microVM)                        │
│                                                                      │
│  ┌─────────────────────┐     ┌──────────────────────────────────┐   │
│  │  App Under Dev       │     │  MCP PostgreSQL Server            │   │
│  │                      │     │  (org-scoped config)              │   │
│  └──────────┬───────────┘     └──────────────┬───────────────────┘   │
│             │                                │                       │
│             └────────────┬───────────────────┘                       │
│                          │ TCP 5432                                   │
│                          ▼                                           │
│             ┌────────────────────────┐                               │
│             │  Network Path          │                               │
│             │  ├─ Zscaler ZPA        │                               │
│             │  └─ Static IP Allowlist│                               │
│             └────────────┬───────────┘                               │
└──────────────────────────┼───────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Customer GCP Project  │
              │                        │
              │  Cloud SQL Auth Proxy  │◄── Google Service Account
              │         │              │    (authenticates proxy)
              │         │ mTLS         │
              │         ▼              │
              │  Cloud SQL PostgreSQL  │
              │  (DB role: devin_dev)  │
              └────────────────────────┘
```

**Key constraint:** Devin sessions run as isolated microVMs with no inherent cloud identity (no AWS IAM role, no GCP service account, no instance metadata). Any authentication to external services must use explicitly provisioned credentials.

## Architecture Options

| Option | GCP Credential on Devin | Customer Infra | Setup Time | Best For |
|--------|------------------------|----------------|------------|----------|
| [A: Customer-Hosted Proxy](#option-a-customer-hosted-proxy) | None — DB password only | GCE/Cloud Run VM with proxy | ~2 hrs | Production / security-sensitive |
| [B: Service Account Key](#option-b-service-account-key-on-devin) | SA key JSON in Devin Secrets | None additional | ~30 min | Quick POC validation |
| [C: Direct Connect](#option-c-direct-connect) | DB password only | None additional | ~15 min | Simplest possible setup |

---

## Option A: Customer-Hosted Proxy

**Recommended for production.** All GCP identity stays on the customer side. Devin holds only a scoped database password — no GCP service account key ever leaves GCP.

This mirrors how human developers typically connect: through a corporate network (e.g., Zscaler ZPA) to a database endpoint, authenticating with a DB user, without holding service account keys on their laptops.

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Devin Session (microVM)                        │
│                                                                      │
│  App Under Dev ──┐                                                  │
│                  ├── TCP 5432 ──► Zscaler ZPA ──┐                   │
│  MCP PostgreSQL ─┘                              │                   │
│                                                  │                   │
│  Devin Secrets:                                  │                   │
│    DB_HOST · DB_USER · DB_PASSWORD · DB_NAME     │                   │
└──────────────────────────────────────────────────┼───────────────────┘
                                                   │
                                                   ▼
              ┌────────────────────────────────────────────────────────┐
              │  Customer GCP Project                                  │
              │                                                        │
              │  ┌────────────────────────────────────┐               │
              │  │  Proxy VM (GCE / Cloud Run)         │               │
              │  │  cloud-sql-proxy listening on :5432  │               │
              │  │  Instance SA: devin-db@project.iam   │               │
              │  │  (native — no key file)              │               │
              │  └──────────────┬───────────────────────┘               │
              │                 │ mTLS                                  │
              │                 ▼                                       │
              │  ┌────────────────────────────────────┐               │
              │  │  Cloud SQL PostgreSQL               │               │
              │  │  (private IP only)                  │               │
              │  │  DB role: devin_dev                 │               │
              │  └────────────────────────────────────┘               │
              └────────────────────────────────────────────────────────┘
```

### Why This Approach

- **No GCP credentials on Devin** — eliminates key rotation, leakage risk, and credential management
- **Cloud SQL can remain private-IP only** — no public IP required
- **Devin blueprint is minimal** — no proxy binary, no gcloud CLI needed
- **Extends existing network patterns** — if Zscaler ZPA already routes Devin traffic (e.g., for GitHub Enterprise), adding Cloud SQL is an incremental ZPA config change

### Setup

See [Customer-Hosted Proxy Setup](docs/option-a-customer-hosted-proxy.md) for detailed steps.

**Summary:**
1. Customer deploys a small GCE VM (or Cloud Run service) with the GSA as its instance service account
2. `cloud-sql-proxy` runs on the VM, listening on port 5432
3. The proxy VM is added as a Zscaler ZPA Application Segment
4. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Option B: Service Account Key on Devin

**Recommended for POC.** Fastest to stand up. Customer generates a GCP service account key, stores it as a Devin secret, and Cloud SQL Auth Proxy runs inside the Devin session.

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Devin Session (microVM)                        │
│                                                                      │
│  App Under Dev ──┐                                                  │
│                  ├── localhost:5432                                  │
│  MCP PostgreSQL ─┘       │                                          │
│                          ▼                                           │
│              cloud-sql-proxy                                        │
│              (authenticates via SA key)                              │
│                          │                                           │
│  Devin Secrets:          │                                           │
│    GCP_SA_KEY · CLOUD_SQL_INSTANCE                                  │
└──────────────────────────┼───────────────────────────────────────────┘
                           │ mTLS (via Zscaler or static IP)
                           ▼
              ┌────────────────────────────────────────────────────────┐
              │  Customer GCP Project                                  │
              │                                                        │
              │  Cloud SQL PostgreSQL                                  │
              │  DB role: devin_dev                                    │
              │                                                        │
              │  GSA: devin-db@project.iam                             │
              │    roles/cloudsql.client                                │
              │    roles/cloudsql.instanceUser                          │
              └────────────────────────────────────────────────────────┘
```

### Why This Approach

- **Fastest to validate** — ~30 minutes from start to connected
- **No customer infrastructure needed** — just a GSA, a key, and network access
- **Cloud SQL Auth Proxy provides mTLS** — encrypted regardless of network path
- **Compatible with IAM DB authentication** — passwordless DB access via the proxy

### Trade-offs

- A GCP service account key (JSON) is stored in Devin Secrets — must be rotated every 90 days
- The key grants `cloudsql.client` + `cloudsql.instanceUser` IAM roles — scope carefully

### Setup

See [Service Account Key Setup](docs/option-b-sa-key-on-devin.md) for detailed steps.

**Summary:**
1. Customer creates a GSA with `roles/cloudsql.client` + `roles/cloudsql.instanceUser`
2. Customer generates a key and provides it to the Devin org admin
3. Devin admin stores `GCP_SA_KEY` and `CLOUD_SQL_INSTANCE` as org-scoped secrets
4. Environment blueprint installs Cloud SQL Auth Proxy in `initialize`, starts it in `maintenance`

---

## Option C: Direct Connect

**Simplest possible setup.** Devin connects directly to Cloud SQL using a standard PostgreSQL connection string. No proxy, no GCP identity — just a database password.

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Devin Session (microVM)                        │
│                                                                      │
│  App Under Dev ──┐                                                  │
│                  ├── TCP 5432 ──► Zscaler ZPA / Static IP ──┐      │
│  MCP PostgreSQL ─┘                                           │      │
│                                                              │      │
│  Devin Secrets:                                              │      │
│    DB_HOST · DB_USER · DB_PASSWORD · DB_NAME                 │      │
└──────────────────────────────────────────────────────────────┼──────┘
                                                               │
                                                               ▼
              ┌────────────────────────────────────────────────────────┐
              │  Customer GCP Project                                  │
              │                                                        │
              │  Cloud SQL PostgreSQL (public IP, SSL required)        │
              │  DB role: devin_dev                                    │
              └────────────────────────────────────────────────────────┘
```

### Why This Approach

- **No additional infrastructure** — no proxy VM, no GCP identity on Devin
- **No Devin blueprint changes needed** — `psql` and libpq are already available
- **Simplest mental model** — standard PostgreSQL over TLS

### Trade-offs

- Cloud SQL must have a **public IP** (unless routed through Zscaler ZPA)
- No mTLS — relies on Cloud SQL's built-in SSL/TLS (server-side cert, not client cert)
- No IAM-based DB authentication — standard password only

### Setup

See [Direct Connect Setup](docs/option-c-direct-connect.md) for detailed steps.

**Summary:**
1. Customer creates a PostgreSQL user and grants schema-scoped permissions
2. Customer adds Devin's static egress IPs to Cloud SQL Authorized Networks (or configures Zscaler)
3. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Cross-Cutting Concerns

### Network Path Options

| Path | When to Use | Setup |
|---|---|---|
| **Zscaler ZPA** | Organization already uses Zscaler for Devin traffic (e.g., GitHub Enterprise) | Add Cloud SQL proxy/instance as a ZPA Application Segment |
| **Static IP Allowlist** | No existing Zscaler setup; direct internet path is acceptable | Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to Cloud SQL Authorized Networks |

### Database Permissions

Create a dedicated PostgreSQL role with schema-scoped access:

```sql
-- Dedicated user for Devin sessions
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';

-- Read-only on shared/reference schemas
GRANT USAGE ON SCHEMA shared_schema TO devin_dev;
GRANT SELECT ON ALL TABLES IN SCHEMA shared_schema TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA shared_schema
  GRANT SELECT ON TABLES TO devin_dev;

-- Read-write on application schema (for CRUD testing)
GRANT USAGE ON SCHEMA app_schema TO devin_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app_schema TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA app_schema
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO devin_dev;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app_schema TO devin_dev;
```

**Permissions guidance:**
- One GSA and one DB role per Devin org (or per app for multi-app setups)
- `SELECT` on all relevant schemas; scoped `INSERT/UPDATE/DELETE` on app schemas
- **No DDL** (`CREATE TABLE`, `ALTER`, `DROP`) unless explicitly required
- **No superuser** — never grant `SUPERUSER`, `CREATEDB`, or `CREATEROLE`

### Google Service Account Scoping (Options A and B)

| IAM Role | Purpose | Required? |
|---|---|---|
| `roles/cloudsql.client` | Connect via Cloud SQL Auth Proxy | Yes |
| `roles/cloudsql.instanceUser` | IAM DB authentication (passwordless) | Recommended |

- **No broader roles** — the GSA should never have `roles/editor`, `roles/owner`, or project-wide access

### Credential Management

| Credential | Storage | Rotation | Notes |
|---|---|---|---|
| GCP SA key (Option B) | Devin org-scoped secret | Every 90 days | Injected as env var at session start; env var removed before snapshot save. Blueprint writes key to `/dev/shm/` (tmpfs) so it never touches disk. |
| DB password (Options A, C) | Devin org-scoped secret | Every 90 days or on personnel change | Standard PostgreSQL password |
| DB host / instance name | Devin org or repo-scoped secret | N/A (not sensitive, but varies per environment) | |

**Security properties of Devin Secrets:**
- Encrypted at rest
- Injected as environment variables at session start
- **Secret env vars are removed before snapshot save** — but files written to disk-backed paths by user scripts *will* persist. Always write sensitive files to tmpfs (`/dev/shm/`) to avoid snapshot capture.
- Org-scoped isolation — one org cannot access another org's secrets

### Ephemeral VM Considerations

Devin sessions are ephemeral microVMs booted from snapshots. This has implications for database connectivity:

| Concern | Impact | Mitigation |
|---|---|---|
| Processes don't survive restart | Cloud SQL Auth Proxy must be restarted each session | `maintenance` blueprint section starts the proxy |
| SA key must be available at session start | Can't bake keys into snapshots (env vars are stripped) | Devin Secrets inject keys as env vars; blueprint writes to `/dev/shm/` (tmpfs) so the file never touches disk |
| Connection state is not preserved | Each session is a fresh connection | Stateless by design — no session affinity needed |
| Blueprint `initialize` persists in snapshot | Binaries installed once stay installed | Install proxy binary in `initialize` |

### Why Not Workload Identity Federation?

GCP Workload Identity Federation (WIF) is the gold-standard for cloud-to-cloud authentication — it eliminates stored credentials entirely by exchanging an external identity (AWS IAM role, OIDC token, SAML assertion) for short-lived GCP tokens.

**WIF is not viable for Devin today** because:
1. Devin VMs have **no AWS IAM identity** — they are isolated microVMs with no instance profile, no IAM role, and no access to the EC2 metadata service
2. Devin does not expose a **per-session OIDC token** — no JWT to exchange
3. No **SAML assertion** is issued for Devin sessions

See [WIF Future Considerations](docs/wif-future-considerations.md) for a detailed analysis of what would need to change to enable WIF.

## File Structure

```
cloud-sql/
├── README.md                                  # This file — overview + 3 options
├── docs/
│   ├── option-a-customer-hosted-proxy.md      # Detailed setup: proxy on GCP side
│   ├── option-b-sa-key-on-devin.md            # Detailed setup: SA key + proxy on Devin
│   ├── option-c-direct-connect.md             # Detailed setup: direct PostgreSQL
│   └── wif-future-considerations.md           # Why WIF doesn't work today + future path
└── examples/
    ├── blueprint-sa-key-proxy.yaml            # Devin blueprint for Option B
    └── blueprint-direct-connect.yaml          # Devin blueprint for Option C
```

## Related Patterns

- [Database Access Patterns](../../database-access/) — MCP server setup, CLI configuration, credential management
- [IAP Tunneling](../iap-tunneling/) — alternative network path via Identity-Aware Proxy
- [Private Service Connect](../private-service-connect/) — private IP for Google APIs and services

## Reference

- [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/postgres/sql-proxy)
- [Cloud SQL IAM Database Authentication](https://cloud.google.com/sql/docs/postgres/authentication)
- [Devin Secrets](https://docs.devin.ai/admin/common-issues#ip-whitelisting)
- [Devin Environment Blueprints](https://docs.devin.ai)
