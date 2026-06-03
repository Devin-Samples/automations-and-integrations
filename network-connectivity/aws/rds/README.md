# AWS RDS Connectivity

Connect Devin to AWS RDS PostgreSQL databases — customer-hosted proxy, IAM credentials, and direct connect options with Zscaler ZPA integration.

> **This guide is AWS-specific, but the architecture follows a provider-agnostic three-layer model** (network path → transport/proxy → identity/auth) that applies equally to GCP Cloud SQL, Azure SQL, and other cloud-hosted databases. See [Generalizing to Other Cloud Providers](#generalizing-to-other-cloud-providers) for cross-cloud mapping.

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
              │  Customer AWS Account  │
              │                        │
              │  RDS Proxy / pgbouncer │◄── IAM Role (attached to EC2/ECS)
              │         │              │    (authenticates proxy)
              │         │ TLS          │
              │         ▼              │
              │  RDS PostgreSQL        │
              │  (DB role: devin_dev)  │
              └────────────────────────┘
```

**Key constraint:** Devin sessions run as isolated microVMs with no inherent cloud identity (no AWS IAM role, no instance metadata service, no GCP service account). Any authentication to external services must use explicitly provisioned credentials.

## Architecture Options

| Option | AWS Credential on Devin | Customer Infra | Setup Time | Best For |
|--------|------------------------|----------------|------------|----------|
| [A: Customer-Hosted Proxy](#option-a-customer-hosted-proxy) | None — DB password only | RDS Proxy (managed) or pgbouncer on EC2 | ~2 hrs | Production / security-sensitive |
| [B: IAM Credentials on Devin](#option-b-iam-credentials-on-devin) | IAM user access key in Devin Secrets | None additional | ~30 min | Quick POC validation |
| [C: Direct Connect](#option-c-direct-connect) | DB password only | None additional | ~15 min | Simplest possible setup |

---

## Option A: Customer-Hosted Proxy

**Recommended for production.** All AWS identity stays on the customer side. Devin holds only a scoped database password — no AWS access key ever leaves the customer's infrastructure.

This mirrors how human developers typically connect: through a corporate network (e.g., Zscaler ZPA) to a database endpoint, authenticating with a DB user, without holding IAM credentials on their laptops.

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
              │  Customer AWS Account                                  │
              │                                                        │
              │  ┌────────────────────────────────────┐               │
              │  │  RDS Proxy (managed)                │               │
              │  │  or pgbouncer on EC2                │               │
              │  │  IAM role: devin-rds-proxy          │               │
              │  │  (native — no access key)           │               │
              │  └──────────────┬───────────────────────┘               │
              │                 │ TLS                                  │
              │                 ▼                                       │
              │  ┌────────────────────────────────────┐               │
              │  │  RDS PostgreSQL                     │               │
              │  │  (private subnets)                  │               │
              │  │  DB role: devin_dev                 │               │
              │  └────────────────────────────────────┘               │
              └────────────────────────────────────────────────────────┘
```

### Why This Approach

- **No AWS credentials on Devin** — eliminates key rotation, leakage risk, and credential management
- **RDS can remain in private subnets** — no public accessibility required
- **Devin blueprint is minimal** — no AWS CLI, no proxy binary needed
- **Extends existing network patterns** — if Zscaler ZPA already routes Devin traffic (e.g., for GitHub Enterprise), adding RDS Proxy is an incremental ZPA config change

### Setup

See [Customer-Hosted Proxy Setup](docs/option-a-customer-hosted-proxy.md) for detailed steps.

**Summary:**
1. Customer deploys RDS Proxy (managed) or pgbouncer on EC2 with an IAM role attached
2. Proxy endpoint exposed to Devin via Zscaler ZPA
3. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Option B: IAM Credentials on Devin

**Recommended for POC.** Fastest to stand up. Customer creates an IAM user with scoped RDS permissions, stores the access key as a Devin secret, and uses `aws rds generate-db-auth-token` for IAM DB authentication.

```
┌──────────────────────────────────────────────────────────────────────┐
│                       Devin Session (microVM)                        │
│                                                                      │
│  App Under Dev ──┐                                                  │
│                  ├── TCP 5432                                        │
│  MCP PostgreSQL ─┘       │                                          │
│                          ▼                                           │
│              aws rds generate-db-auth-token                         │
│              (authenticates via IAM access key)                      │
│                          │                                           │
│  Devin Secrets:          │                                           │
│    AWS_ACCESS_KEY_ID · AWS_SECRET_ACCESS_KEY                        │
│    DB_HOST · DB_NAME · DB_USER                                      │
└──────────────────────────┼───────────────────────────────────────────┘
                           │ TLS (via Zscaler or static IP)
                           ▼
              ┌────────────────────────────────────────────────────────┐
              │  Customer AWS Account                                  │
              │                                                        │
              │  RDS PostgreSQL                                        │
              │  IAM DB authentication enabled                         │
              │  DB role: devin_iam                                    │
              │                                                        │
              │  IAM user: devin-db-user                               │
              │    policy: rds-db:connect + rds:DescribeDBInstances    │
              └────────────────────────────────────────────────────────┘
```

### Why This Approach

- **Fastest to validate** — ~30 minutes from start to connected
- **No customer infrastructure needed** — just an IAM user, a policy, and network access
- **IAM DB auth provides short-lived tokens** — 15-minute token lifetime, auto-refreshable
- **Or just use password auth** — IAM user only needed for RDS API access, DB password for data access

### Trade-offs

- An AWS IAM access key is stored in Devin Secrets — must be rotated every 90 days
- The access key grants `rds-db:connect` + `rds:DescribeDBInstances` — scope carefully

### Setup

See [IAM Credentials Setup](docs/option-b-iam-credentials-on-devin.md) for detailed steps.

**Summary:**
1. Customer creates an IAM user with `rds-db:connect` and `rds:DescribeDBInstances` permissions
2. Customer generates an access key and provides it to the Devin org admin
3. Devin admin stores `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and DB connection info as org-scoped secrets
4. Environment blueprint installs AWS CLI in `initialize`, generates auth tokens in `maintenance`

---

## Option C: Direct Connect

**Simplest possible setup.** Devin connects directly to RDS using a standard PostgreSQL connection string. No proxy, no AWS identity — just a database password.

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
              │  Customer AWS Account                                  │
              │                                                        │
              │  RDS PostgreSQL (publicly accessible, SG-restricted)   │
              │  DB role: devin_dev                                    │
              └────────────────────────────────────────────────────────┘
```

### Why This Approach

- **No additional infrastructure** — no proxy, no AWS identity on Devin
- **No Devin blueprint changes needed** — `psql` and libpq are already available
- **Simplest mental model** — standard PostgreSQL over TLS

### Trade-offs

- RDS must be **publicly accessible** (unless routed through Zscaler ZPA)
- No IAM-based DB authentication — standard password only
- Security Group must allowlist Devin's static egress IPs

### Setup

See [Direct Connect Setup](docs/option-c-direct-connect.md) for detailed steps.

**Summary:**
1. Customer creates a PostgreSQL user and grants schema-scoped permissions
2. Customer enables public accessibility on RDS and adds Devin's static egress IPs to the Security Group (or configures Zscaler)
3. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Cross-Cutting Concerns

### Network Path Options

| Path | When to Use | Setup |
|---|---|---|
| **Zscaler ZPA** | Organization already uses Zscaler for Devin traffic (e.g., for GitHub Enterprise) | Add RDS Proxy endpoint or RDS instance as a ZPA Application Segment |
| **Static IP Allowlist** | No existing Zscaler setup; direct internet path is acceptable | Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to the RDS Security Group |

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
- One IAM user and one DB role per Devin org (or per app for multi-app setups)
- `SELECT` on all relevant schemas; scoped `INSERT/UPDATE/DELETE` on app schemas
- **No DDL** (`CREATE TABLE`, `ALTER`, `DROP`) unless explicitly required
- **No superuser** — never grant `rds_superuser` or `CREATEDB`

### IAM User Scoping (Option B)

| IAM Permission | Purpose | Required? |
|---|---|---|
| `rds-db:connect` | Generate IAM DB auth tokens | Yes (for IAM DB auth) |
| `rds:DescribeDBInstances` | Discover instance endpoint and port | Recommended |

- **No broader policies** — the IAM user should never have `AdministratorAccess`, `AmazonRDSFullAccess`, or account-wide access
- Use a custom IAM policy with resource-scoped ARNs

### Credential Management

| Credential | Storage | Rotation | Notes |
|---|---|---|---|
| AWS access key (Option B) | Devin org-scoped secret | Every 90 days | Injected as env var at session start; env var removed before snapshot save. Blueprint writes key to `/dev/shm/` (tmpfs) so it never touches disk. |
| DB password (Options A, C) | Devin org-scoped secret | Every 90 days or on personnel change | Standard PostgreSQL password |
| DB host / instance endpoint | Devin org or repo-scoped secret | N/A (not sensitive, but varies per environment) | |

**Security properties of Devin Secrets:**
- Encrypted at rest
- Injected as environment variables at session start
- **Secret env vars are removed before snapshot save** — but files written to disk-backed paths by user scripts *will* persist. Always write sensitive files to tmpfs (`/dev/shm/`) to avoid snapshot capture.
- Org-scoped isolation — one org cannot access another org's secrets

### Ephemeral VM Considerations

Devin sessions are ephemeral microVMs booted from snapshots. This has implications for database connectivity:

| Concern | Impact | Mitigation |
|---|---|---|
| Processes don't survive restart | AWS CLI auth token generation must re-run each session | `maintenance` blueprint section generates fresh tokens |
| Access key must be available at session start | Can't bake keys into snapshots (env vars are stripped) | Devin Secrets inject keys as env vars; blueprint writes to `/dev/shm/` (tmpfs) so the file never touches disk |
| Connection state is not preserved | Each session is a fresh connection | Stateless by design — no session affinity needed |
| Blueprint `initialize` persists in snapshot | Binaries installed once stay installed | Install AWS CLI in `initialize` |

### Why Not IAM Role Assumption?

AWS IAM Role Assumption (via `AssumeRole` or instance profiles) is the gold-standard for AWS authentication — it eliminates stored access keys entirely by leveraging attached IAM roles for short-lived credentials.

**IAM Role Assumption is not viable for Devin today** because:
1. Devin VMs have **no AWS IAM identity** — they are isolated Firecracker microVMs with no instance profile, no IAM role, and no access to the EC2 metadata service (`169.254.169.254`)
2. The Devin platform does not expose a **per-session OIDC token** — no JWT to exchange via `AssumeRoleWithWebIdentity`
3. No **SAML assertion** is issued for Devin sessions

AWS is the hosting layer for Devin's infrastructure, but sessions are fully isolated — there is no AWS identity available inside the microVM.

See [WIF / IAM Role Future Considerations](docs/wif-future-considerations.md) for a detailed analysis of what would need to change to enable credential-less authentication.

## File Structure

```
rds/
├── README.md                                  # This file — overview + 3 options
├── docs/
│   ├── option-a-customer-hosted-proxy.md      # Detailed setup: RDS Proxy / pgbouncer on customer side
│   ├── option-b-iam-credentials-on-devin.md   # Detailed setup: IAM access key + auth token on Devin
│   ├── option-c-direct-connect.md             # Detailed setup: direct PostgreSQL over TLS
│   └── wif-future-considerations.md           # Why IAM role assumption doesn't work today + future path
└── examples/
    ├── blueprint-iam-auth.yaml                # Devin blueprint for Option B
    └── blueprint-direct-connect.yaml          # Devin blueprint for Option C
```

## Generalizing to Other Cloud Providers

This guide is AWS RDS-specific, but the architecture follows a **three-layer model** that applies to any cloud-hosted database. Only the middle layers change per provider — the network path and the overall pattern are the same.

### Three-Layer Model

```
┌─────────────────────────────────────────────────────────────────┐
│  Layer 1: Network Path (cloud-agnostic)                        │
│  How Devin's traffic reaches the database network               │
│  ├─ Zscaler ZPA          (zero-trust, existing corp path)       │
│  ├─ Static IP allowlist  (simplest, Devin egress IPs)           │
│  ├─ VPN                  (full subnet routing)                  │
│  └─ Cloud tunnel         (SSM / Bastion / IAP)                  │
├─────────────────────────────────────────────────────────────────┤
│  Layer 2: Transport / Proxy (provider-specific)                 │
│  Optional proxy for mTLS, connection pooling, IAM auth          │
│  ├─ AWS:   RDS Proxy / pgbouncer / direct TLS                   │
│  ├─ GCP:   Cloud SQL Auth Proxy                                 │
│  └─ Azure: Private Endpoint / direct TLS                         │
├─────────────────────────────────────────────────────────────────┤
│  Layer 3: Identity / Auth (provider-specific)                   │
│  How the connection authenticates to the database               │
│  ├─ AWS:   IAM DB auth  or  DB password                          │
│  ├─ GCP:   GSA + IAM DB auth  or  DB password                   │
│  └─ Azure: AAD auth  or  SQL auth password                       │
└─────────────────────────────────────────────────────────────────┘
```

### Option Patterns Across Providers

The three options documented here map to equivalent patterns on other clouds:

| Pattern | AWS (this guide) | GCP Equivalent | Azure Equivalent |
|---------|------------------|----------------|------------------|
| **A: Customer-hosted proxy** | RDS Proxy or pgbouncer on EC2, exposed via Zscaler | Cloud SQL Auth Proxy on GCE/Cloud Run, exposed via Zscaler | Azure SQL Private Endpoint, exposed via Zscaler or ExpressRoute |
| **B: Cloud credential on Devin** | AWS IAM user access key → `aws rds generate-db-auth-token` | GCP SA key → Cloud SQL Auth Proxy in session | Azure AD service principal → token-based SQL auth |
| **C: Direct connect** | PostgreSQL over TLS, Security Group allowlist | PostgreSQL over TLS, Authorized Networks | Azure SQL over TLS, firewall IP rules |

### What Stays the Same Across Providers

- **Network path** — Zscaler ZPA and static IP allowlisting work identically regardless of whether the target is RDS, Cloud SQL, or Azure SQL
- **Devin Secrets** — credential storage and injection is provider-agnostic
- **Blueprint structure** — `initialize` (install tooling), `maintenance` (start proxy/tunnel), `knowledge` (connection info)
- **Database permissions model** — dedicated read/read-write role, no DDL, no superuser
- **Ephemeral VM considerations** — proxy must restart each session, credentials via env vars, sensitive files to `/dev/shm/`

### What Changes Per Provider

- **Proxy binary and flags** — RDS Proxy (managed) / pgbouncer vs `cloud-sql-proxy` vs direct Azure connection
- **IAM user / service account setup** — IAM user vs GSA vs Azure AD service principal
- **Cloud-native auth mechanism** — RDS IAM DB auth vs Cloud SQL IAM DB auth vs Azure AD token auth
- **Network allowlist configuration** — Security Groups vs Cloud SQL Authorized Networks vs Azure SQL firewall rules

For the GCP equivalent of this guide, see [GCP Cloud SQL Connectivity](../../gcp/cloud-sql/). For provider-agnostic database access patterns (MCP setup, CLI configuration, credential management), see [Database Access Patterns](../../database-access/).

## Related Patterns

- [Database Access Patterns](../../database-access/) — MCP server setup, CLI configuration, credential management
- [SSM Port Forwarding](../ssm-port-forwarding/) — alternative network path via Systems Manager
- [Client VPN](../client-vpn/) — full subnet VPN access
- [PrivateLink](../privatelink/) — service-to-service private connectivity

## Reference

- [Amazon RDS Proxy](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/rds-proxy.html)
- [RDS IAM Database Authentication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/UsingWithRDS.IAMDBAuth.html)
- [Devin Secrets](https://docs.devin.ai/product-guides/secrets)
- [Devin Static IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting)
- [Devin Environment Blueprints](https://docs.devin.ai)
