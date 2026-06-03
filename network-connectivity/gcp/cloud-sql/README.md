# GCP Cloud SQL Connectivity

Connect Devin to GCP Cloud SQL PostgreSQL databases — customer-hosted proxy, service account key, and direct connect options.

> **Network path is only required when there is no public route to the target resource.** If Cloud SQL has a public IP and you allowlist Devin's static egress IPs (or use Authorized Networks), no proxy or tunnel is needed. When private networking is required, several options exist: cloud-native tunnels like [IAP Tunneling](../iap-tunneling/), zero-trust proxies such as Zscaler ZPA, VPN, or Private Service Connect. Choose the option that fits your existing infrastructure.

> **This guide is GCP-specific, but the architecture follows a provider-agnostic three-layer model** (network path → transport/proxy → identity/auth) that applies equally to AWS RDS, Azure SQL, and other cloud-hosted databases. See [Generalizing to Other Cloud Providers](#generalizing-to-other-cloud-providers) for cross-cloud mapping.

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
│             │  Network Path (if no   │                               │
│             │  public route exists)  │                               │
│             │  ├─ Static IP Allowlist│                               │
│             │  ├─ IAP Tunneling      │                               │
│             │  ├─ Zscaler ZPA        │                               │
│             │  └─ VPN / PSC          │                               │
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

This mirrors how human developers typically connect: through a corporate network path (e.g., a zero-trust proxy like Zscaler ZPA, a VPN, or a cloud-native tunnel like IAP) to a database endpoint, authenticating with a DB user, without holding service account keys on their laptops.

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Devin Session (microVM)                        │
│                                                                      │
│  App Under Dev ──┐                                                  │
│                  ├── TCP 5432 ──► Network Path ─┐                   │
│  MCP PostgreSQL ─┘     (ZPA / IAP / VPN / etc.) │                   │
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
- **Extends existing network patterns** — if you already use a proxy or tunnel for Devin traffic (e.g., Zscaler ZPA for GitHub Enterprise, or IAP for other GCP resources), adding Cloud SQL is an incremental configuration change on whichever path you already have

### Setup

See [Customer-Hosted Proxy Setup](docs/option-a-customer-hosted-proxy.md) for detailed steps.

**Summary:**
1. Customer deploys a small GCE VM (or Cloud Run service) with the GSA as its instance service account
2. `cloud-sql-proxy` runs on the VM, listening on port 5432
3. The proxy VM is exposed to Devin via an existing network path (Zscaler ZPA, IAP tunnel, static IP allowlist, etc.)
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
                           │ mTLS (via network path — see options below)
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
│                  ├── TCP 5432 ──► Network Path ─────────────┐      │
│  MCP PostgreSQL ─┘   (static IP / IAP / ZPA / VPN)          │      │
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

- Cloud SQL must have a **public IP** (unless routed through a private network path such as IAP tunneling, Zscaler ZPA, or VPN)
- No mTLS — relies on Cloud SQL's built-in SSL/TLS (server-side cert, not client cert)
- No IAM-based DB authentication — standard password only

### Setup

See [Direct Connect Setup](docs/option-c-direct-connect.md) for detailed steps.

**Summary:**
1. Customer creates a PostgreSQL user and grants schema-scoped permissions
2. Customer adds Devin's static egress IPs to Cloud SQL Authorized Networks (or configures a private network path — IAP, Zscaler ZPA, VPN, etc.)
3. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Cross-Cutting Concerns

### Network Path Options

| Path | When to Use | Setup |
|---|---|---|
| **Static IP Allowlist** | Simplest option; target has a public IP | Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to Cloud SQL Authorized Networks |
| **IAP Tunneling** | Target is private; you prefer a cloud-native tunnel with no VPN | See [IAP Tunneling](../iap-tunneling/) — identity-aware TCP forwarding, free, no public IPs needed |
| **Zscaler ZPA** | Organization already uses Zscaler for Devin traffic (e.g., GitHub Enterprise) | Add Cloud SQL proxy/instance as a ZPA Application Segment |
| **VPN** | Multiple private resources need full subnet routing | See [Cloud VPN](https://cloud.google.com/network-connectivity/docs/vpn) or [Devin VPN docs](https://docs.devin.ai/onboard-devin/vpn) |

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

## Generalizing to Other Cloud Providers

This guide is GCP Cloud SQL-specific, but the architecture follows a **three-layer model** that applies to any cloud-hosted database. Only the middle layers change per provider — the network path and the overall pattern are the same.

### Three-Layer Model

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: Network Path (cloud-agnostic)                        │
│  How Devin's traffic reaches the database network               │
│  ├─ Static IP allowlist  (simplest — public target, Devin IPs)  │
│  ├─ Cloud tunnel         (SSM / Bastion / IAP — no VPN needed)  │
│  ├─ Zscaler ZPA          (zero-trust proxy, if already in use)  │
│  ├─ VPN                  (full subnet routing)                  │
│  └─ Private Service Connect (dedicated deployment only)          │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Transport / Proxy (provider-specific)                 │
│  Optional proxy for mTLS, connection pooling, IAM auth          │
│  ├─ GCP:   Cloud SQL Auth Proxy                                 │
│  ├─ AWS:   RDS Proxy / direct TLS                                │
│  └─ Azure: Private Endpoint / direct TLS                         │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Identity / Auth (provider-specific)                   │
│  How the connection authenticates to the database               │
│  ├─ GCP:   GSA + IAM DB auth  or  DB password                   │
│  ├─ AWS:   IAM DB auth  or  DB password                          │
│  └─ Azure: AAD auth  or  SQL auth password                       │
└─────────────────────────────────────────────────────────────────┘
```

### Option Patterns Across Providers

The three options documented here map to equivalent patterns on other clouds:

| Pattern | GCP (this guide) | AWS Equivalent | Azure Equivalent |
|---------|------------------|----------------|------------------|
| **A: Customer-hosted proxy** | Cloud SQL Auth Proxy on GCE/Cloud Run, exposed via network path (ZPA, IAP, static IP, etc.) | RDS Proxy or pgbouncer on EC2, exposed via network path (ZPA, SSM, static IP, etc.) | Azure SQL Private Endpoint, exposed via ExpressRoute or network path |
| **B: Cloud credential on Devin** | GCP SA key → Cloud SQL Auth Proxy in session | AWS IAM user access key → `aws rds generate-db-auth-token` | Azure AD service principal → token-based SQL auth |
| **C: Direct connect** | PostgreSQL over TLS, Authorized Networks | PostgreSQL over TLS, Security Group allowlist | Azure SQL over TLS, firewall IP rules |

### What Stays the Same Across Providers

- **Network path** — static IP allowlisting, cloud-native tunnels (SSM, IAP, Bastion), Zscaler ZPA, and VPN all work identically regardless of whether the target is Cloud SQL, RDS, or Azure SQL
- **Devin Secrets** — credential storage and injection is provider-agnostic
- **Blueprint structure** — `initialize` (install tooling), `maintenance` (start proxy/tunnel), `knowledge` (connection info)
- **Database permissions model** — dedicated read/read-write role, no DDL, no superuser
- **Ephemeral VM considerations** — proxy must restart each session, credentials via env vars, sensitive files to `/dev/shm/`

### What Changes Per Provider

- **Proxy binary and flags** — `cloud-sql-proxy` vs `aws rds generate-db-auth-token` vs direct Azure connection
- **IAM role / service account setup** — GSA vs IAM user/role vs Azure AD service principal
- **Cloud-native auth mechanism** — Cloud SQL IAM DB auth vs RDS IAM auth vs Azure AD token auth
- **Network allowlist configuration** — Cloud SQL Authorized Networks vs Security Groups vs Azure SQL firewall rules

For provider-agnostic database access patterns (MCP setup, CLI configuration, credential management), see [Database Access Patterns](../../database-access/).

## Related Patterns

- [Database Access Patterns](../../database-access/) — MCP server setup, CLI configuration, credential management
- [IAP Tunneling](../iap-tunneling/) — alternative network path via Identity-Aware Proxy
- [Private Service Connect](../private-service-connect/) — private IP for Google APIs and services

## Reference

- [Cloud SQL Auth Proxy](https://cloud.google.com/sql/docs/postgres/sql-proxy)
- [Cloud SQL IAM Database Authentication](https://cloud.google.com/sql/docs/postgres/authentication)
- [Devin Secrets](https://docs.devin.ai/product-guides/secrets)
- [Devin Environment Blueprints](https://docs.devin.ai)
