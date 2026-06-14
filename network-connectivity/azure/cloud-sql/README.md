# Azure Database for PostgreSQL Connectivity

Connect Devin to Azure Database for PostgreSQL Flexible Server — customer-hosted private endpoint, service principal, and direct connect options.

> **Network path is only required when there is no public route to the target resource.** If the Flexible Server has a public endpoint and you allowlist Devin's static egress IPs, no tunnel or private endpoint is needed. When private networking is required, several options exist: [Azure Bastion Tunneling](../bastion-tunneling/), Zscaler ZPA, [VPN Gateway](../vpn-gateway/), or [Private Endpoints](../private-endpoints/). Choose the option that fits your existing infrastructure.

> **This guide is Azure-specific, but the architecture follows a provider-agnostic three-layer model** (network path → transport/proxy → identity/auth) that applies equally to AWS RDS, GCP Cloud SQL, and other cloud-hosted databases. See [GCP Cloud SQL](../../gcp/cloud-sql/README.md#generalizing-to-other-cloud-providers) for the cross-cloud mapping.

## Architecture

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  +---------------------+     +----------------------------------+   |
|  |  App Under Dev       |     |  MCP PostgreSQL Server            |   |
|  |                      |     |  (org-scoped config)              |   |
|  +----------+-----------+     +--------------+-------------------+   |
|             |                                |                       |
|             +------------+-------------------+                       |
|                          | TCP 5432                                   |
|                          v                                           |
|             +------------------------+                               |
|             |  Network Path (if no   |                               |
|             |  public route exists)  |                               |
|             |  +- Static IP Allowlist|                               |
|             |  +- Zscaler ZPA        |                               |
|             |  +- VPN Gateway        |                               |
|             |  +- Bastion Tunneling  |                               |
|             +------------+-----------+                               |
+------------------------------+---------------------------------------+
                               |
                               v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  Azure Database for PostgreSQL                      |
              |  Flexible Server                                    |
              |  (TLS enforced, Entra ID or password auth)         |
              |  DB role: devin_dev                                 |
              +----------------------------------------------------+
```

**Key constraint:** Devin sessions run as isolated microVMs with no inherent cloud identity (no AWS IAM role, no Azure Managed Identity, no instance metadata service). Any authentication to external services must use explicitly provisioned credentials.

## Architecture Options

| Option | Azure Credential on Devin | Customer Infra | Setup Time | Best For |
|--------|--------------------------|----------------|------------|----------|
| [A: Customer-Hosted Private Endpoint](#option-a-customer-hosted-private-endpoint) | None -- DB password only | Private Endpoint + Zscaler/VPN | ~2 hrs | Production / security-sensitive |
| [B: Service Principal on Devin](#option-b-service-principal-on-devin) | SP client ID + secret in Devin Secrets | None additional | ~30 min | Quick POC validation |
| [C: Direct Connect](#option-c-direct-connect) | None -- DB password only | None additional | ~15 min | Simplest possible setup |

---

## Option A: Customer-Hosted Private Endpoint

**Production ready** All Azure identity stays on the customer side. Devin holds only a scoped database password -- no Azure credentials on Devin.

This mirrors how human developers typically connect: through a corporate network (e.g., Zscaler ZPA or VPN Gateway) to a database endpoint, authenticating with a DB user, without holding Azure service principal secrets on their laptops.

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  App Under Dev --+                                                   |
|                  +-- TCP 5432 --> Zscaler ZPA --+                    |
|  MCP PostgreSQL -+                              |                    |
|                                                  |                    |
|  Devin Secrets:                                  |                    |
|    DB_HOST . DB_USER . DB_PASSWORD . DB_NAME     |                    |
+--------------------------------------------------+--------------------+
                                                   |
                                                   v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  +----------------------------------------------+  |
              |  |  Private Endpoint                             |  |
              |  |  (private IP in customer VNet)                |  |
              |  |  maps to Flexible Server                     |  |
              |  +---------------------+------------------------+  |
              |                        | private link                |
              |                        v                             |
              |  +----------------------------------------------+  |
              |  |  Azure Database for PostgreSQL                |  |
              |  |  Flexible Server (VNet-integrated)            |  |
              |  |  DB role: devin_dev                           |  |
              |  +----------------------------------------------+  |
              +----------------------------------------------------+
```

### Why This Approach

- **No Azure credentials on Devin** -- eliminates secret rotation, leakage risk, and credential management
- **Flexible Server public endpoint can remain disabled** -- traffic flows entirely over private link
- **Devin blueprint is minimal** -- no Azure CLI, no token acquisition logic
- **Extends existing network patterns** -- if Zscaler ZPA already routes Devin traffic (e.g., for Azure DevOps), adding PostgreSQL is an incremental ZPA config change

### Setup

See [Customer-Hosted Private Endpoint Setup](docs/option-a-customer-hosted-endpoint.md) for detailed steps.

**Summary:**
1. Customer creates an Azure Private Endpoint for the Flexible Server (or uses VNet integration)
2. The private endpoint's IP is exposed to Devin via Zscaler ZPA (or VPN Gateway)
3. Customer creates a PostgreSQL user (`devin_dev`) with schema-scoped permissions
4. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Option B: Service Principal on Devin

**Recommended to start with.** Fastest to stand up with Azure AD (Entra ID) authentication. Customer creates an Entra ID service principal, stores its client ID and secret as Devin secrets, and Devin acquires an Entra ID access token at session start for token-based PostgreSQL authentication.

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  App Under Dev --+                                                   |
|                  +-- TCP 5432                                        |
|  MCP PostgreSQL -+       |                                           |
|                          v                                           |
|  maintenance script acquires Entra ID token:                         |
|    az login --service-principal                                      |
|    az account get-access-token --resource-type oss-rdbms             |
|                          |                                           |
|  Devin Secrets:          |                                           |
|    AZURE_CLIENT_ID . AZURE_CLIENT_SECRET . AZURE_TENANT_ID          |
+------------------------------+---------------------------------------+
                               | TLS (via Zscaler or static IP)
                               v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  Azure Database for PostgreSQL                      |
              |  Flexible Server                                    |
              |  (Entra ID auth enabled)                            |
              |  Entra ID principal mapped to PG role               |
              |    devin_dev (contained DB role)                    |
              |                                                     |
              |  Service Principal: devin-db-sp                     |
              +----------------------------------------------------+
```

### Why This Approach

- **Fastest to validate** -- ~30 minutes from start to connected
- **No customer infrastructure needed** -- just a service principal and network access
- **Token-based auth** -- short-lived Entra ID tokens (default 1 hour), no long-lived DB passwords
- **Compatible with Entra-only mode** -- works even if password auth is disabled on the server

### Trade-offs

- An Entra ID client secret is stored in Devin Secrets -- must be rotated per your organization's policy (default max lifetime: 2 years, recommended: 6 months)
- The service principal needs no broad Azure AD roles -- it only authenticates to PostgreSQL via an Entra ID access token

### Setup

See [Service Principal on Devin Setup](docs/option-b-service-principal-on-devin.md) for detailed steps.

**Summary:**
1. Customer creates an Entra ID app registration and service principal
2. Customer adds the service principal as a PostgreSQL role in the Flexible Server
3. Devin admin stores `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `PG_HOST`, `DB_NAME` as org-scoped secrets
4. Environment blueprint installs Azure CLI in `initialize`, acquires token in `maintenance`

---

## Option C: Direct Connect

**Simplest possible setup.** Devin connects directly to Azure Database for PostgreSQL using a standard `postgresql://` connection string over TLS. No Azure identity, no service principal -- just a database password.

Azure Database for PostgreSQL Flexible Server **enforces TLS by default** (`require_secure_transport = ON`). Even with this simplest option, transport encryption is guaranteed unless the customer has explicitly disabled it.

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  App Under Dev --+                                                   |
|                  +-- TCP 5432 --> Zscaler ZPA / Static IP --+        |
|  MCP PostgreSQL -+                                          |        |
|                                                              |        |
|  Devin Secrets:                                              |        |
|    DB_HOST . DB_USER . DB_PASSWORD . DB_NAME                 |        |
+--------------------------------------------------------------+--------+
                                                               |
                                                               v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  Azure Database for PostgreSQL Flexible Server      |
              |  (public endpoint, TLS enforced)                    |
              |  DB role: devin_dev (password auth)                 |
              +----------------------------------------------------+
```

### Why This Approach

- **No additional infrastructure** -- no private endpoint, no service principal, no Azure CLI on Devin
- **No Devin blueprint changes needed** -- `psql` and libpq are already available in Devin sessions
- **Simplest mental model** -- standard PostgreSQL over TLS

### Trade-offs

- Flexible Server **public access must be enabled** (unless routed through Zscaler ZPA to a private endpoint)
- No Entra ID token-based auth -- standard PostgreSQL password only
- No short-lived tokens -- DB password should be rotated every 90 days

### Setup

See [Direct Connect Setup](docs/option-c-direct-connect.md) for detailed steps.

**Summary:**
1. Customer creates a PostgreSQL user and grants schema-scoped permissions
2. Customer adds Devin's static egress IPs to the Flexible Server firewall rules (or configures Zscaler)
3. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Cross-Cutting Concerns

### Network Path Options

| Path | When to Use | Setup |
|---|---|---|
| **Static IP Allowlist** | Simplest option; target has a public endpoint | Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to Flexible Server firewall rules |
| **Zscaler ZPA** | Organization already uses Zscaler for Devin traffic (e.g., for Azure DevOps) | Add the Flexible Server private endpoint or public hostname as a ZPA Application Segment |
| **VPN Gateway** | Multiple private resources need full subnet routing | See [Azure VPN Gateway](../vpn-gateway/) or [Devin VPN docs](https://docs.devin.ai/onboard-devin/vpn) |
| **Azure Bastion** | Quick tunnel to a single private resource | See [Bastion Tunneling](../bastion-tunneling/) — native SSH tunneling, no public IPs on VMs |

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
- One service principal and one DB role per Devin org (or per app for multi-app setups)
- `SELECT` on all relevant schemas; scoped `INSERT/UPDATE/DELETE` on app schemas
- **No DDL** (`CREATE TABLE`, `ALTER`, `DROP`) unless explicitly required

### Service Principal Scoping (Option B)

| Entra ID Role / Permission | Purpose | Required? |
|---|---|---|
| (none) | Minimal -- SP only needs to authenticate to get a token | Recommended default |
| `Directory.Reader` | Resolve Entra ID group memberships | Only if the PG role maps to an Entra group |

- The service principal authenticates to PostgreSQL via an Entra ID access token
- DB-level access is controlled entirely through the PostgreSQL role mapped to the SP
- **No broader Azure roles** -- the service principal should never have `Contributor`, `Owner`, or subscription-level access

### Credential Management

| Credential | Storage | Rotation | Notes |
|---|---|---|---|
| Entra ID client secret (Option B) | Devin org-scoped secret | Per org policy (recommended: 6 months) | Blueprint writes token (not the secret itself) to `/dev/shm/` (tmpfs) so it never touches disk. Client secret injected as env var; stripped before snapshot save. |
| PostgreSQL password (Options A, C) | Devin org-scoped secret | Every 90 days or on personnel change | Standard PostgreSQL password |
| DB host / server name | Devin org or repo-scoped secret | N/A (not sensitive, but varies per environment) | Format: `SERVER.postgres.database.azure.com` |

**Security properties of Devin Secrets:**
- Encrypted at rest
- Injected as environment variables at session start
- **Secret env vars are removed before snapshot save** -- but files written to disk-backed paths by user scripts *will* persist. Always write sensitive files to tmpfs (`/dev/shm/`) to avoid snapshot capture.
- Org-scoped isolation -- one org cannot access another org's secrets

### Ephemeral VM Considerations

Devin sessions are ephemeral microVMs booted from snapshots. This has implications for database connectivity:

| Concern | Impact | Mitigation |
|---|---|---|
| Processes don't survive restart | Azure CLI login and token acquisition must run each session | `maintenance` blueprint section acquires fresh Entra ID token |
| Client secret must be available at session start | Can't bake secrets into snapshots (env vars are stripped) | Devin Secrets inject credentials as env vars; blueprint writes tokens to `/dev/shm/` (tmpfs) |
| Connection state is not preserved | Each session is a fresh connection | Stateless by design -- no session affinity needed |
| Blueprint `initialize` persists in snapshot | Binaries installed once stay installed | Install Azure CLI in `initialize` |

### Why Not Managed Identity / Federated Identity?

Azure [Managed Identity](https://learn.microsoft.com/en-us/azure/active-directory/managed-identities-azure-resources/overview) is the gold standard for Azure-to-Azure authentication -- it eliminates stored credentials entirely by using the VM's inherent identity via the Instance Metadata Service (IMDS).

**Managed Identity is not viable for Devin today** because:
1. Devin VMs have **no Azure Managed Identity** -- they are isolated Firecracker microVMs, not Azure VMs
2. Devin VMs have **no Instance Metadata Service (IMDS)** -- the `169.254.169.254` endpoint is not available
3. Devin does not expose a **per-session OIDC token** -- no JWT to exchange via federated credentials

See [WIF / Federated Identity Future Considerations](docs/wif-future-considerations.md) for a detailed analysis of what would need to change to enable credential-less authentication.

## File Structure

```
cloud-sql/
+-- README.md                                    # This file -- overview + 3 options
+-- docs/
|   +-- option-a-customer-hosted-endpoint.md     # Detailed setup: Private Endpoint + Zscaler
|   +-- option-b-service-principal-on-devin.md   # Detailed setup: SP + Entra ID token auth
|   +-- option-c-direct-connect.md               # Detailed setup: direct password auth
|   +-- wif-future-considerations.md             # Why federated identity doesn't work today
+-- examples/
    +-- blueprint-service-principal.yaml          # Devin blueprint for Option B
    +-- blueprint-direct-connect.yaml            # Devin blueprint for Option C
```

## Related Patterns

- [Database Access Patterns](../../database-access/) -- MCP server setup, CLI configuration, credential management
- [Azure Bastion Tunneling](../bastion-tunneling/) -- alternative network path via Azure Bastion
- [Azure Private Endpoints](../private-endpoints/) -- private IP for Azure PaaS services
- [Azure VPN Gateway](../vpn-gateway/) -- full subnet VPN for multi-service access
- [Azure SQL (SQL Server)](../sql/) -- connectivity patterns for Azure SQL Database (SQL Server engine)

## Reference

- [Azure Database for PostgreSQL Flexible Server](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/overview)
- [Entra ID Authentication for Azure PostgreSQL](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-azure-ad-authentication)
- [Azure Private Link for PostgreSQL](https://learn.microsoft.com/en-us/azure/postgresql/flexible-server/concepts-networking-private-link)
- [Devin Secrets](https://docs.devin.ai/product-guides/secrets)
- [Devin Static Egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting)
