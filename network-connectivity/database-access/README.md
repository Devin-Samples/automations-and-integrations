# Database Access Patterns

> Connect Devin to databases — MCP server setup, CLI configuration, credential management, and private database networking.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│                         Devin Session (VM)                            │
│                                                                       │
│  ┌─────────────────────┐     ┌──────────────────────────────────┐    │
│  │  MCP Database Server │     │  CLI Tools (psql, mysql, etc.)   │    │
│  │  (org-scoped config) │     │  (installed via blueprint)       │    │
│  │                      │     │                                   │    │
│  │  $DB_CONNECTION_URL  │     │  Credentials from Devin Secrets  │    │
│  └──────────┬───────────┘     └──────────────┬───────────────────┘    │
│             │                                │                        │
│             └────────────┬───────────────────┘                        │
│                          │                                            │
│                          ▼                                            │
│             ┌────────────────────────┐                                │
│             │  Network Path          │                                │
│             │  ├─ Direct (IP allow)  │                                │
│             │  ├─ SSM Tunnel         │                                │
│             │  ├─ VPN                │                                │
│             │  └─ PrivateLink        │                                │
│             └────────────┬───────────┘                                │
└──────────────────────────┼────────────────────────────────────────────┘
                           │
                           ▼
              ┌────────────────────────┐
              │  Your Database         │
              │  (RDS, Cloud SQL,      │
              │   Azure SQL, on-prem)  │
              └────────────────────────┘
```

## Access Model 1: MCP Database Servers

MCP servers are the recommended approach. They provide structured access, schema discovery, and are required for the Data Analyst Agent (DANA).

### Supported Databases

| Database | MCP Name | Auth Method | Setup |
|---|---|---|---|
| PostgreSQL | PostgreSQL | Connection string | `$DB_CONNECTION_URL` in Secrets |
| MySQL | MySQL | Connection string | `$DB_CONNECTION_URL` in Secrets |
| SQL Server | SQL Server | Connection string | `$DB_CONNECTION_URL` in Secrets |
| Amazon Redshift | Redshift | Connection string + credentials | Connection string + IAM or user/pass |
| Snowflake | Snowflake | Account + credentials | Account ID, user, password, warehouse |
| Google BigQuery | BigQuery | OAuth or service account | OAuth flow or service account JSON |
| Neon | Neon | OAuth | OAuth flow |
| Supabase | Supabase | Personal access token | Token in Secrets |
| Cloud SQL | Cloud SQL | OAuth | Google OAuth flow |

### Setup via MCP Marketplace

1. Navigate to **Settings > MCP Marketplace**
2. Search for your database engine (e.g., "PostgreSQL")
3. Click **Enable**
4. Provide credentials — store sensitive values as Devin Secrets first, then reference them with `$SECRET_NAME`
5. Click **Save**, then **Test listing tools** to verify connectivity

### Custom MCP Server (STDIO Example)

If your database MCP isn't in the marketplace, add it manually via **Add Your Own**:

**Transport:** STDIO

```json
{
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-postgres", "$POSTGRES_CONNECTION_URL"],
  "env": {}
}
```

Store `POSTGRES_CONNECTION_URL` as a Devin Secret:
```
postgresql://devin_readonly:PASSWORD@db.example.com:5432/mydb?sslmode=require
```

### Custom MCP Server (HTTP/SSE Example)

If you run a remote MCP server for your database:

**Transport:** HTTP (recommended over SSE)

```json
{
  "url": "https://mcp.internal.example.com/db",
  "auth": {
    "method": "auth_header",
    "key": "Authorization",
    "value": "Bearer $MCP_DB_TOKEN"
  }
}
```

## Access Model 2: CLI-Based

Install database CLIs in the Devin environment blueprint for direct shell access.

### PostgreSQL

**Blueprint (`initialize`):**
```yaml
initialize: |
  sudo apt-get update && sudo apt-get install -y postgresql-client
```

**Blueprint (`knowledge`):**
```yaml
knowledge:
  - name: database
    contents: |
      Connect to the database: psql "$POSTGRES_CONNECTION_URL"
```

**Devin Secret:** `POSTGRES_CONNECTION_URL`
```
postgresql://devin_dev:PASSWORD@db.example.com:5432/development?sslmode=require
```

### MySQL

**Blueprint (`initialize`):**
```yaml
initialize: |
  sudo apt-get update && sudo apt-get install -y mysql-client
```

**Devin Secret:** `MYSQL_CONNECTION_URL`
```
mysql://devin_dev:PASSWORD@db.example.com:3306/development
```

### MongoDB

**Blueprint (`initialize`):**
```yaml
initialize: |
  curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | sudo gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg
  echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-7.0.list
  sudo apt-get update && sudo apt-get install -y mongosh
```

**Devin Secret:** `MONGO_URI`
```
mongodb+srv://devin_readonly:PASSWORD@cluster.example.mongodb.net/mydb
```

### Redis

**Blueprint (`initialize`):**
```yaml
initialize: |
  sudo apt-get update && sudo apt-get install -y redis-tools
```

**Devin Secret:** `REDIS_URL`
```
redis://devin:PASSWORD@redis.example.com:6379/0
```

## Credential Management

### Creating Database Users

Create dedicated database users for Devin with minimal permissions:

**PostgreSQL:**
```sql
-- Read-only user for analytics / DANA
CREATE USER devin_readonly WITH PASSWORD 'SECURE_PASSWORD';
GRANT CONNECT ON DATABASE production TO devin_readonly;
GRANT USAGE ON SCHEMA public TO devin_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO devin_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO devin_readonly;

-- Read-write user for development
CREATE USER devin_dev WITH PASSWORD 'SECURE_PASSWORD';
GRANT CONNECT ON DATABASE development TO devin_dev;
GRANT USAGE ON SCHEMA public TO devin_dev;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO devin_dev;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO devin_dev;
```

**MySQL:**
```sql
-- Read-only user
CREATE USER 'devin_readonly'@'%' IDENTIFIED BY 'SECURE_PASSWORD';
GRANT SELECT ON production.* TO 'devin_readonly'@'%';

-- Read-write user
CREATE USER 'devin_dev'@'%' IDENTIFIED BY 'SECURE_PASSWORD';
GRANT SELECT, INSERT, UPDATE, DELETE ON development.* TO 'devin_dev'@'%';
```

### Storing Credentials in Devin

| Secret Scope | When to Use | How to Set |
|---|---|---|
| **Enterprise** | Database shared across all teams (rare) | Settings > Devin's base environment > Secrets tab |
| **Organization** | Team-specific database (typical) | Settings > Secrets |
| **Repository** | Project-specific database | Environment blueprint `.env` or repo-scoped secrets |

**Org secrets take precedence over enterprise secrets** with the same name — this lets teams override shared defaults.

### Rotation

1. **Create new credentials** in your database platform
2. **Update the Devin Secret** via Settings > Secrets or the [Secrets API](https://docs.devin.ai/api-reference/v1/secrets/list-secrets)
3. **Test connectivity** by starting a new session
4. **Revoke old credentials** in your database platform

For Devin service user API keys (not database credentials), the [Rotate API key](https://docs.devin.ai/api-reference/v3/service-users/rotate-enterprise-service-user-api-key) endpoint supports graceful rollover with `revoke_current=false`.

**Rotation cadence:** Every 90 days or per your organization's security policy. Rotate immediately on suspected compromise or personnel changes.

## Networking: Reaching Private Databases

Most production databases are not publicly accessible. Choose the networking pattern based on your cloud provider and security requirements.

### IP Allowlisting (Simplest)

For cloud databases with IP-based firewall rules:

1. Get Devin's static IPs from [docs.devin.ai/integrations/self-hosted-scm-artifacts](https://docs.devin.ai/integrations/self-hosted-scm-artifacts)
2. Add to your database's security group / firewall rules
3. Require SSL/TLS on the connection

**Works with:** RDS, Cloud SQL, Azure SQL, any database behind an IP-based firewall.

### SSM Port Forwarding (AWS Private Databases)

For RDS/Aurora in private VPC subnets — no VPN required:

1. Deploy the [SSM port-forwarding stack](../aws/ssm-port-forwarding/) targeting your database port
2. Store the SSM IAM credentials as Devin Secrets (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`)
3. Add tunnel establishment to the environment blueprint:

```yaml
initialize: |
  # Install SSM plugin (if not already present)
  curl -fsSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" -o /tmp/ssm-plugin.deb
  sudo dpkg -i /tmp/ssm-plugin.deb

maintenance: |
  # Establish SSM tunnel to RDS (runs at session start)
  aws ssm start-session \
    --target $SSM_INSTANCE_ID \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$RDS_ENDPOINT\"],\"portNumber\":[\"5432\"],\"localPortNumber\":[\"5432\"]}" &
  sleep 5  # Wait for tunnel to establish
```

4. MCP or CLI connects to `localhost:5432` (tunneled to private RDS)

### VPN (Multi-Resource Access)

For environments where Devin needs to reach multiple private resources (database + internal APIs + registries):

- See [VPN Configuration](https://docs.devin.ai/onboard-devin/vpn) for Devin's VPN support
- See [Client VPN pattern](../aws/client-vpn/) (AWS), [VPN Gateway](../azure/vpn-gateway/) (Azure) for cloud-specific setups

### PrivateLink (Enterprise / Dedicated Deployment)

For enterprise customers on Devin's Dedicated Deployment with AWS PrivateLink:

- Traffic stays on AWS backbone — no public internet exposure
- See [Dedicated Deployment Private Networking](https://docs.devin.ai/enterprise/deployment/dedicated_saas_private_networking)

## Credential Isolation

**Database credentials are NOT shared across Devin Organizations**, even within the same enterprise.

Each organization has completely isolated:
- **Secrets** — Connection strings and passwords
- **MCP configurations** — Database server connections
- **Environment blueprints** — CLI tools and tunnel configurations

This means Org A's production database credentials are invisible to Org B — critical for multi-team enterprises and partner accounts hosting multiple customers.

## Troubleshooting

| Issue | Likely Cause | Fix |
|---|---|---|
| MCP "Test listing tools" fails | Credentials incorrect or network unreachable | Verify secret values; check IP allowlist includes Devin's IPs |
| Connection timeout | Database not reachable from Devin's network | Add IP allowlist, configure VPN/SSM tunnel, or check security groups |
| Authentication failed | Wrong username/password or expired credentials | Update Devin Secret with current credentials |
| SSL/TLS handshake failure | Database requires specific TLS version or CA cert | Add `sslmode=require` to connection string; install CA cert in blueprint |
| DANA shows "no data sources" | No MCP database connection configured | Set up at least one database MCP server in the org |
| Tunnel drops mid-session | SSM session timeout or VPN reconnection | Increase session timeout; add reconnection logic to blueprint maintenance |

## References

- [MCP Marketplace](https://docs.devin.ai/work-with-devin/mcp) — MCP server configuration, transport types
- [Data Analyst Agent](https://docs.devin.ai/work-with-devin/data-analyst) — DANA usage and supported databases
- [Secrets Management](https://docs.devin.ai/product-guides/secrets) — Storing and scoping credentials
- [VPN Configuration](https://docs.devin.ai/onboard-devin/vpn) — Connecting to internal networks
- [Self-Hosted SCM & Artifacts](https://docs.devin.ai/integrations/self-hosted-scm-artifacts) — IP addresses and SSL requirements
- [Environment Configuration](https://docs.devin.ai/onboard-devin/environment) — Blueprint setup
- [SSM Port Forwarding](../aws/ssm-port-forwarding/) — AWS tunnel to private VPC resources
