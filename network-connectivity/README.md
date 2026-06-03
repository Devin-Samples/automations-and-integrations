# Network Connectivity

Patterns and deployable infrastructure for connecting Devin to private resources that are not reachable from the public internet — self-hosted Artifactory, GitHub Enterprise Server, private databases, internal APIs, and similar endpoints behind corporate firewalls or inside cloud VPCs.

## Which Pattern Should I Use?

| Pattern | Cloud | Complexity | Cost | Best For |
|---|---|---|---|---|
| **[SSM Port Forwarding](aws/ssm-port-forwarding/)** | AWS | Low | ~$0.06/hr (VPC endpoints) | Quick access to a single private endpoint; no VPN client needed |
| **[Client VPN](aws/client-vpn/)** | AWS | Medium | ~$0.15/hr + $0.05/conn | Multiple private resources; full subnet-level routing |
| **[PrivateLink](aws/privatelink/)** | AWS | Low | ~$0.01/hr + data | Service-to-service connectivity; no VPC peering required |
| **[Bastion Tunneling](azure/bastion-tunneling/)** | Azure | Low | ~$0.19/hr | Quick access to Azure VMs; native SSH/RDP tunneling |
| **[Private Endpoints](azure/private-endpoints/)** | Azure | Low | ~$0.01/hr + data | Azure PaaS services (Key Vault, Storage, SQL) over private IP |
| **[VPN Gateway](azure/vpn-gateway/)** | Azure | Medium | ~$0.04/hr+ | Full site-to-site or point-to-site connectivity |
| **[IAP Tunneling](gcp/iap-tunneling/)** | GCP | Low | Free (IAP) | Quick access to GCP VMs; identity-aware TCP forwarding |
| **[Private Service Connect](gcp/private-service-connect/)** | GCP | Low | ~$0.01/hr + data | Google-managed services over private IP |
| **[Cloud SQL](gcp/cloud-sql/)** | GCP | Low–Med | Varies by option | Cloud SQL PostgreSQL — customer-hosted proxy, SA key, or direct connect |
| **[Azure SQL](azure/sql/)** | Azure | Low–Med | Varies by option | Azure SQL Database — private endpoint, service principal, or direct connect |
| **[RDS](aws/rds/)** | AWS | Low–Med | Varies by option | RDS PostgreSQL — customer-hosted proxy, IAM credentials, or direct connect |
| **[Database Access](database-access/)** | Any | Varies | Depends on tunnel | MCP or CLI database connectivity — credential setup, rotation, auth providers |

### Decision Guide

**Start here:** What does Devin need to reach?

1. **A single service on one port** (e.g., Artifactory on :8081, GHES on :443)
   - AWS → **SSM Port Forwarding** — no VPN, no jump box, encrypted tunnel through SSM
   - Azure → **Bastion Tunneling** — native tunnel to VM, no public IP needed
   - GCP → **IAP Tunneling** — identity-aware TCP tunnel, no public IP needed

2. **Multiple services across a private subnet** (e.g., Artifactory + database + internal APIs)
   - AWS → **Client VPN** — full subnet routing through an OpenVPN-compatible endpoint
   - Azure → **VPN Gateway (P2S)** — point-to-site VPN with certificate or AAD auth
   - GCP → **Cloud VPN** — IPsec tunnel with subnet-level routing

3. **A managed cloud service** (e.g., RDS, Azure SQL, Cloud Storage) that you want to access privately
   - AWS → **PrivateLink** — expose a VPC endpoint for the service
   - Azure → **Private Endpoints** — private IP for PaaS services
   - GCP → **Private Service Connect** — private IP for Google APIs and services

### Security Comparison

| Pattern | Auth Method | Network Exposure | Encryption |
|---|---|---|---|
| SSM Port Forwarding | IAM user/role (SigV4) | Zero — no inbound rules, no public IPs | TLS (SSM channel) |
| Client VPN | Certificates or AD | VPN endpoint is internet-facing | TLS 1.2+ (OpenVPN) |
| PrivateLink | IAM policies | Zero — traffic stays on AWS backbone | TLS (service-level) |
| Bastion Tunneling | Azure AD / SSH keys | Bastion is managed, no VM public IP | TLS (Bastion channel) |
| IAP Tunneling | Google IAM (OAuth2) | Zero — no inbound rules, no public IPs | TLS (IAP channel) |

## Directory Structure

```
network-connectivity/
├── README.md                          # This file — decision guide
├── database-access/                   # ✓ Available — MCP + CLI database connectivity patterns
├── aws/
│   ├── ssm-port-forwarding/           # ✓ Available — SSM tunnel to private VPC resources
│   ├── client-vpn/                    # ✓ Available — Full subnet VPN access
│   ├── privatelink/                   # ✓ Available — Service-to-service private connectivity
│   └── rds/                           # ✓ Available — RDS PostgreSQL connectivity
├── azure/
│   ├── bastion-tunneling/             # ✓ Available — Bastion native tunneling to Azure VMs
│   ├── private-endpoints/             # ✓ Available — Private IP for Azure PaaS services
│   ├── vpn-gateway/                   # ✓ Available — P2S/S2S VPN for full subnet routing
│   └── sql/                           # ✓ Available — Azure SQL Database connectivity
└── gcp/
    ├── iap-tunneling/                 # ✓ Available — IAP TCP forwarding to GCP VMs
    ├── private-service-connect/       # ✓ Available — Private IP for Google APIs and services
    └── cloud-sql/                     # ✓ Available — Cloud SQL PostgreSQL connectivity
```

## Devin Environment Integration

Each pattern includes instructions for integrating with Devin's environment configuration so the connectivity is established automatically at session start. The general approach:

1. **`initialize`** — Install any required CLI tools or plugins (e.g., SSM Session Manager Plugin, Azure CLI, `gcloud`)
2. **Secrets** — Store credentials (IAM access keys, service principal secrets, service account keys) as Devin secrets
3. **`maintenance`** — Establish the tunnel or VPN connection at session start

See individual pattern READMEs for specific instructions.

## Cloud Database Connectivity

Connecting Devin to a cloud-hosted database (Cloud SQL, RDS, Azure SQL, etc.) follows a **three-layer model**:

| Layer | What It Does | Cloud-Agnostic? |
|-------|-------------|-----------------|
| **1. Network Path** | Gets Devin's traffic to the database network (Zscaler ZPA, static IP allowlist, VPN, tunnel) | Yes — same regardless of provider |
| **2. Transport / Proxy** | Optional proxy for mTLS, connection pooling, or IAM-based auth (Cloud SQL Auth Proxy, RDS Proxy, etc.) | No — provider-specific binary and config |
| **3. Identity / Auth** | How the connection authenticates (IAM DB auth, service account, managed identity, DB password) | No — provider-specific IAM setup |

**Available provider-specific guides:**
- **AWS** → [RDS Connectivity](aws/rds/) — three architecture options (proxy, IAM credentials, direct connect) with detailed setup and example blueprints
- **GCP** → [Cloud SQL Connectivity](gcp/cloud-sql/) — three architecture options with detailed setup, cross-cloud mapping table, and example blueprints
- **Azure** → [Azure SQL Connectivity](azure/sql/) — three architecture options (private endpoint, service principal, direct connect) with example blueprints

For provider-agnostic database access (MCP server setup, CLI configuration, credential management), see the dedicated [Database Access](database-access/) guide. It covers:
- MCP vs. CLI access models and when to use each
- Credential creation, rotation, and auth provider configuration
- Per-database setup examples (PostgreSQL, MySQL, MongoDB, Snowflake, etc.)
- Integration with the networking patterns above (SSM tunnels, VPN, PrivateLink) for private databases

## FAQ

### My backend only accepts traffic from specific remote servers. How can Devin access it for end-to-end testing?

Devin sessions run on Cognition-managed infrastructure, so your backend won't see traffic from an IP you control. You have four options, from simplest to most secure:

1. **IP Allowlisting** — Add [Devin's static egress IPs](https://docs.devin.ai/integrations/self-hosted-scm-artifacts) to your backend's firewall or security group. This is the fastest path if your backend supports IP-based access control.

2. **Tunnel (single service)** — Deploy a lightweight relay instance in your cloud and tunnel traffic through it. No VPN client needed, no inbound rules, no public IPs on the target:
   - **AWS** → [SSM Port Forwarding](aws/ssm-port-forwarding/) — encrypted tunnel via Systems Manager
   - **Azure** → [Bastion Tunneling](azure/bastion-tunneling/) — native tunnel through Azure Bastion
   - **GCP** → [IAP Tunneling](gcp/iap-tunneling/) — identity-aware TCP forwarding, free

3. **VPN (multiple services)** — If Devin needs to reach several private resources (backend + database + internal APIs), establish a full VPN connection at session start:
   - See [Devin VPN docs](https://docs.devin.ai/onboard-devin/vpn) for built-in OpenVPN support
   - Cloud-specific: [AWS Client VPN](aws/client-vpn/), [Azure VPN Gateway](azure/vpn-gateway/)

4. **PrivateLink / Private Endpoints** — For enterprise customers on dedicated deployment, keep all traffic on the cloud backbone:
   - [AWS PrivateLink](aws/privatelink/)
   - [Azure Private Endpoints](azure/private-endpoints/)
   - [GCP Private Service Connect](gcp/private-service-connect/)

All patterns include [Devin environment integration](#devin-environment-integration) instructions so the connectivity is established automatically every session.

### Can Devin connect to a database behind a firewall?

Yes. Follow the [three-layer model](#cloud-database-connectivity):

1. **Network path** (Layer 1) — Use one of the tunnel or VPN patterns above to make the database reachable from Devin's session
2. **Transport / proxy** (Layer 2) — If needed, run a provider-specific proxy (e.g., [Cloud SQL Auth Proxy](gcp/cloud-sql/) for GCP, RDS Proxy for AWS) for mTLS and IAM auth
3. **Identity / auth** (Layer 3) — Store credentials as Devin Secrets, enable the appropriate MCP in Settings > MCP Marketplace

For cloud-hosted databases, see [Cloud Database Connectivity](#cloud-database-connectivity) for provider-specific guides. For general database access patterns (MCP setup, CLI, credential management), see [Database Access](database-access/).

### Does Devin have a static IP I can allowlist?

Yes. Devin's egress traffic comes from a set of static IPs listed in the [Self-Hosted SCM & Artifacts documentation](https://docs.devin.ai/integrations/self-hosted-scm-artifacts). Add these IPs to your firewall, security group, or network ACL. This is the simplest approach but does expose your service to any traffic from those IPs — for tighter security, use a tunnel or VPN pattern instead.

### How do I make the tunnel start automatically every Devin session?

Each pattern's README includes a **Devin Environment Integration** section. The general recipe:

1. **`initialize`** — Install CLI tools (SSM plugin, Azure CLI, gcloud) once in the environment snapshot
2. **Secrets** — Store cloud credentials as Devin Secrets (org or repo scope)
3. **`maintenance`** — Run the tunnel command in the background at session start

See the [Devin environment docs](https://docs.devin.ai/onboard-devin/environment) for blueprint configuration.

### What if I'm on Azure or GCP instead of AWS?

Each cloud has equivalent patterns. See the cloud-specific guides:

- **Azure:** [Bastion Tunneling](azure/bastion-tunneling/) (single VM), [Private Endpoints](azure/private-endpoints/) (PaaS services), [VPN Gateway](azure/vpn-gateway/) (full subnet)
- **GCP:** [IAP Tunneling](gcp/iap-tunneling/) (single VM/service), [Private Service Connect](gcp/private-service-connect/) (Google APIs)

The [decision guide](#decision-guide) above helps you pick the right pattern for your scenario.

### Can I use multiple patterns together?

Yes. For example, you might use **SSM Port Forwarding** to reach an Artifactory instance on port 8081, and separately configure a **database MCP** with IP allowlisting for an RDS instance that has public access with security-group restrictions. Each tunnel or endpoint is independent — add multiple `maintenance` commands to your blueprint.

## Reference

- [Devin Environment Setup](https://docs.devin.ai/onboard-devin/environment-yaml)
- [Devin VPN Configuration](https://docs.devin.ai/onboard-devin/vpn)
- [Devin Static IPs](https://docs.devin.ai/integrations/self-hosted-scm-artifacts)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview)
- [GCP Identity-Aware Proxy](https://cloud.google.com/iap/docs/using-tcp-forwarding)
