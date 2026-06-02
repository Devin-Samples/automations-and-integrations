# Azure SQL Connectivity

Connect Devin to Azure SQL databases — customer-hosted private endpoint, Azure AD service principal, and direct connect options with Zscaler ZPA integration.

> **This guide is Azure-specific, but the architecture follows a provider-agnostic three-layer model** (network path -> transport/proxy -> identity/auth) that applies equally to AWS RDS, GCP Cloud SQL, and other cloud-hosted databases. See [Generalizing to Other Cloud Providers](../../gcp/cloud-sql/README.md#generalizing-to-other-cloud-providers) for the cross-cloud mapping.

## Architecture

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  +---------------------+     +----------------------------------+   |
|  |  App Under Dev       |     |  MCP SQL Server                   |   |
|  |                      |     |  (org-scoped config)              |   |
|  +----------+-----------+     +--------------+-------------------+   |
|             |                                |                       |
|             +------------+-------------------+                       |
|                          | TCP 1433                                   |
|                          v                                           |
|             +------------------------+                               |
|             |  Network Path          |                               |
|             |  +- Zscaler ZPA        |                               |
|             |  +- Static IP Allowlist|                               |
|             +------------+-----------+                               |
+------------------------------+---------------------------------------+
                               |
                               v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  Azure SQL Database                                 |
              |  (TLS enforced, AAD or SQL auth)                    |
              |  DB user: devin_dev                                 |
              +----------------------------------------------------+
```

**Key constraint:** Devin sessions run as isolated microVMs with no inherent cloud identity (no AWS IAM role, no Azure Managed Identity, no instance metadata service). Any authentication to external services must use explicitly provisioned credentials.

## Architecture Options

| Option | Azure Credential on Devin | Customer Infra | Setup Time | Best For |
|--------|--------------------------|----------------|------------|----------|
| [A: Customer-Hosted Private Endpoint](#option-a-customer-hosted-private-endpoint) | None -- SQL auth password only | Private Endpoint + Zscaler/ExpressRoute | ~2 hrs | Production / security-sensitive |
| [B: Service Principal on Devin](#option-b-service-principal-on-devin) | SP client ID + secret in Devin Secrets | None additional | ~30 min | Quick POC validation |
| [C: Direct Connect](#option-c-direct-connect) | None -- SQL auth password only | None additional | ~15 min | Simplest possible setup |

---

## Option A: Customer-Hosted Private Endpoint

**Recommended for production.** All Azure identity stays on the customer side. Devin holds only a scoped SQL auth password -- no Azure credentials on Devin.

This mirrors how human developers typically connect: through a corporate network (e.g., Zscaler ZPA or ExpressRoute) to a database endpoint, authenticating with a DB user, without holding Azure service principal secrets on their laptops.

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  App Under Dev --+                                                   |
|                  +-- TCP 1433 --> Zscaler ZPA --+                    |
|  MCP SQL Server -+                              |                    |
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
              |  |  maps to Azure SQL logical server             |  |
              |  +---------------------+------------------------+  |
              |                        | private link                |
              |                        v                             |
              |  +----------------------------------------------+  |
              |  |  Azure SQL Database                           |  |
              |  |  (public endpoint disabled)                   |  |
              |  |  DB user: devin_dev                           |  |
              |  +----------------------------------------------+  |
              +----------------------------------------------------+
```

### Why This Approach

- **No Azure credentials on Devin** -- eliminates secret rotation, leakage risk, and credential management
- **Azure SQL public endpoint can remain disabled** -- traffic flows entirely over private link
- **Devin blueprint is minimal** -- no Azure CLI, no token acquisition logic
- **Extends existing network patterns** -- if Zscaler ZPA already routes Devin traffic (e.g., for Azure DevOps), adding Azure SQL is an incremental ZPA config change

### Setup

See [Customer-Hosted Private Endpoint Setup](docs/option-a-customer-hosted-endpoint.md) for detailed steps.

**Summary:**
1. Customer creates an Azure Private Endpoint for the Azure SQL logical server
2. The private endpoint's IP is exposed to Devin via Zscaler ZPA (or ExpressRoute)
3. Customer creates a SQL auth user (`devin_dev`) with schema-scoped permissions
4. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Option B: Service Principal on Devin

**Recommended for POC.** Fastest to stand up with Azure AD (Entra ID) authentication. Customer creates an Azure AD service principal, stores its client ID and secret as Devin secrets, and Devin acquires AAD tokens at session start for token-based SQL authentication.

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  App Under Dev --+                                                   |
|                  +-- TCP 1433                                        |
|  MCP SQL Server -+       |                                           |
|                          v                                           |
|  maintenance script acquires AAD token:                              |
|    az login --service-principal                                      |
|    az account get-access-token --resource https://database.windows.  |
|                          |                                           |
|  Devin Secrets:          |                                           |
|    AZURE_CLIENT_ID . AZURE_CLIENT_SECRET . AZURE_TENANT_ID          |
+------------------------------+---------------------------------------+
                               | TLS (via Zscaler or static IP)
                               v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  Azure SQL Database                                 |
              |  (AAD-only or mixed auth)                           |
              |  External user mapped to service principal          |
              |    devin_dev (contained DB user)                    |
              |                                                     |
              |  Service Principal: devin-db-sp                     |
              |    Directory.Reader (if needed)                     |
              +----------------------------------------------------+
```

### Why This Approach

- **Fastest to validate** -- ~30 minutes from start to connected
- **No customer infrastructure needed** -- just a service principal and network access
- **Token-based auth** -- short-lived AAD tokens (default 1 hour), no long-lived DB passwords
- **Compatible with AAD-only mode** -- works even if SQL auth is disabled on the server

### Trade-offs

- An Azure AD client secret is stored in Devin Secrets -- must be rotated per your organization's policy (default max lifetime: 2 years, recommended: 6 months)
- The service principal needs at minimum `Directory.Reader` if you want to resolve AAD groups; otherwise no Azure AD roles are required

### Setup

See [Service Principal on Devin Setup](docs/option-b-service-principal-on-devin.md) for detailed steps.

**Summary:**
1. Customer creates an Azure AD app registration and service principal
2. Customer adds the service principal as an external user in Azure SQL
3. Devin admin stores `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET`, `AZURE_SQL_SERVER`, `DB_NAME` as org-scoped secrets
4. Environment blueprint installs Azure CLI in `initialize`, acquires token in `maintenance`

---

## Option C: Direct Connect

**Simplest possible setup.** Devin connects directly to Azure SQL using a standard SQL connection string over TLS. No Azure identity, no service principal -- just a SQL auth user and password.

Azure SQL **always enforces TLS** -- there is no option to disable it. Even with this simplest option, transport encryption is guaranteed.

```
+----------------------------------------------------------------------+
|                       Devin Session (microVM)                        |
|                                                                      |
|  App Under Dev --+                                                   |
|                  +-- TCP 1433 --> Zscaler ZPA / Static IP --+        |
|  MCP SQL Server -+                                          |        |
|                                                              |        |
|  Devin Secrets:                                              |        |
|    DB_HOST . DB_USER . DB_PASSWORD . DB_NAME                 |        |
+--------------------------------------------------------------+--------+
                                                               |
                                                               v
              +----------------------------------------------------+
              |  Customer Azure Subscription                        |
              |                                                     |
              |  Azure SQL Database (public endpoint, TLS enforced) |
              |  DB user: devin_dev (SQL auth)                      |
              +----------------------------------------------------+
```

### Why This Approach

- **No additional infrastructure** -- no private endpoint, no service principal, no Azure CLI on Devin
- **No Devin blueprint changes needed** -- `sqlcmd` or standard SQL client libraries connect directly
- **Simplest mental model** -- standard SQL auth over TLS (always encrypted by Azure SQL)

### Trade-offs

- Azure SQL **public endpoint must be enabled** (unless routed through Zscaler ZPA to a private endpoint)
- No AAD token-based auth -- standard SQL auth password only
- No short-lived tokens -- DB password should be rotated every 90 days

### Setup

See [Direct Connect Setup](docs/option-c-direct-connect.md) for detailed steps.

**Summary:**
1. Customer creates a SQL auth user and grants schema-scoped permissions
2. Customer adds Devin's static egress IPs to Azure SQL server firewall rules (or configures Zscaler)
3. Devin stores `DB_HOST`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` as org-scoped secrets

---

## Cross-Cutting Concerns

### Network Path Options

| Path | When to Use | Setup |
|---|---|---|
| **Zscaler ZPA** | Organization already uses Zscaler for Devin traffic (e.g., for Azure DevOps) | Add Azure SQL private endpoint or server as a ZPA Application Segment |
| **Static IP Allowlist** | No existing Zscaler setup; direct internet path is acceptable | Add [Devin's static egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting) to Azure SQL server firewall rules |
| **ExpressRoute** | Organization has existing ExpressRoute circuit to Azure | Route Devin traffic via Zscaler ZPA to an on-prem/VNet gateway with ExpressRoute peering |

### Database Permissions

Create a dedicated SQL user with schema-scoped access:

```sql
-- Create a dedicated SQL auth login and user for Devin
CREATE LOGIN devin_dev WITH PASSWORD = 'SECURE_PASSWORD';

-- In the target database:
CREATE USER devin_dev FOR LOGIN devin_dev;

-- Read-only on shared/reference schemas
ALTER ROLE db_datareader ADD MEMBER devin_dev;

-- Selective write access on application schema
GRANT INSERT, UPDATE, DELETE ON SCHEMA::app_schema TO devin_dev;

-- Explicit deny on DDL
DENY CREATE TABLE TO devin_dev;
DENY ALTER ANY SCHEMA TO devin_dev;
```

**Permissions guidance:**
- Dedicated `devin_dev` SQL user per Devin org (or per app for multi-app setups)
- `db_datareader` for read access across all tables; scoped `INSERT/UPDATE/DELETE` on app schemas
- **No `db_owner`** -- never grant database ownership roles
- **No DDL** (`CREATE TABLE`, `ALTER`, `DROP`) unless explicitly required

### Service Principal Scoping (Option B)

| Azure AD Role / Permission | Purpose | Required? |
|---|---|---|
| `Directory.Reader` | Resolve Azure AD group memberships | Only if the SQL external user maps to a group |
| (none) | Minimal -- SP only needs to authenticate | Recommended default |

- The service principal authenticates to Azure SQL via an AAD access token
- DB-level access is controlled entirely through the contained database user (mapped to the SP) and SQL permissions
- **No broader Azure roles** -- the service principal should never have `Contributor`, `Owner`, or subscription-level access

### Credential Management

| Credential | Storage | Rotation | Notes |
|---|---|---|---|
| Azure AD client secret (Option B) | Devin org-scoped secret | Per org policy (recommended: 6 months) | Blueprint writes token (not the secret itself) to `/dev/shm/` (tmpfs) so it never touches disk. Client secret injected as env var; stripped before snapshot save. |
| SQL auth password (Options A, C) | Devin org-scoped secret | Every 90 days or on personnel change | Standard SQL Server password |
| DB host / server name | Devin org or repo-scoped secret | N/A (not sensitive, but varies per environment) | Format: `SERVER.database.windows.net` |

**Security properties of Devin Secrets:**
- Encrypted at rest
- Injected as environment variables at session start
- **Secret env vars are removed before snapshot save** -- but files written to disk-backed paths by user scripts *will* persist. Always write sensitive files to tmpfs (`/dev/shm/`) to avoid snapshot capture.
- Org-scoped isolation -- one org cannot access another org's secrets

### Ephemeral VM Considerations

Devin sessions are ephemeral microVMs booted from snapshots. This has implications for database connectivity:

| Concern | Impact | Mitigation |
|---|---|---|
| Processes don't survive restart | Azure CLI login and token acquisition must run each session | `maintenance` blueprint section acquires fresh AAD token |
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
sql/
+-- README.md                                  # This file -- overview + 3 options
+-- docs/
|   +-- option-a-customer-hosted-endpoint.md   # Detailed setup: Private Endpoint + Zscaler
|   +-- option-b-service-principal-on-devin.md # Detailed setup: SP + AAD token auth
|   +-- option-c-direct-connect.md             # Detailed setup: direct SQL auth
|   +-- wif-future-considerations.md           # Why federated identity doesn't work today
+-- examples/
    +-- blueprint-service-principal.yaml        # Devin blueprint for Option B
    +-- blueprint-direct-connect.yaml          # Devin blueprint for Option C
```

## Related Patterns

- [Database Access Patterns](../../database-access/) -- MCP server setup, CLI configuration, credential management
- [Azure Bastion Tunneling](../bastion-tunneling/) -- alternative network path via Azure Bastion
- [Azure Private Endpoints](../private-endpoints/) -- private IP for Azure PaaS services
- [Azure VPN Gateway](../vpn-gateway/) -- full subnet VPN for multi-service access

## Reference

- [Azure SQL Database](https://learn.microsoft.com/en-us/azure/azure-sql/database/)
- [Azure AD Authentication for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/authentication-aad-overview)
- [Azure Private Link for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)
- [Devin Secrets](https://docs.devin.ai/product-guides/secrets)
- [Devin Static Egress IPs](https://docs.devin.ai/admin/common-issues#ip-whitelisting)
