# Network Connectivity

Patterns and deployable infrastructure for connecting Devin to private resources that are not reachable from the public internet — self-hosted Artifactory, GitHub Enterprise Server, private databases, internal APIs, and similar endpoints behind corporate firewalls or inside cloud VPCs.

## Which Pattern Should I Use?

| Pattern | Cloud | Complexity | Cost | Best For |
|---|---|---|---|---|
| **[SSM Port Forwarding](aws/ssm-port-forwarding/)** | AWS | Low | ~$0.06/hr (VPC endpoints) | Quick access to a single private endpoint; no VPN client needed |
| **Client VPN** | AWS | Medium | ~$0.15/hr + $0.05/conn | Multiple private resources; full subnet-level routing |
| **PrivateLink** | AWS | Low | ~$0.01/hr + data | Service-to-service connectivity; no VPC peering required |
| **[Bastion Tunneling](azure/bastion-tunneling/)** | Azure | Low | ~$0.19/hr | Quick access to Azure VMs; native SSH/RDP tunneling |
| **Private Endpoints** | Azure | Low | ~$0.01/hr + data | Azure PaaS services (Key Vault, Storage, SQL) over private IP |
| **VPN Gateway** | Azure | Medium | ~$0.04/hr+ | Full site-to-site or point-to-site connectivity |
| **[IAP Tunneling](gcp/iap-tunneling/)** | GCP | Low | Free (IAP) | Quick access to GCP VMs; identity-aware TCP forwarding |
| **Private Service Connect** | GCP | Low | ~$0.01/hr + data | Google-managed services over private IP |

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
├── aws/
│   ├── ssm-port-forwarding/           # ✓ Available — SSM tunnel to private VPC resources
│   ├── client-vpn/                    # Planned
│   └── privatelink/                   # Planned
├── azure/
│   ├── bastion-tunneling/             # Planned
│   ├── private-endpoints/             # Planned
│   └── vpn-gateway/                   # Planned
└── gcp/
    ├── iap-tunneling/                 # Planned
    └── private-service-connect/       # Planned
```

## Devin Environment Integration

Each pattern includes instructions for integrating with Devin's environment configuration so the connectivity is established automatically at session start. The general approach:

1. **`initialize`** — Install any required CLI tools or plugins (e.g., SSM Session Manager Plugin, Azure CLI, `gcloud`)
2. **Secrets** — Store credentials (IAM access keys, service principal secrets, service account keys) as Devin secrets
3. **`maintenance`** — Establish the tunnel or VPN connection at session start

See individual pattern READMEs for specific instructions.

## Reference

- [Devin Environment Setup](https://docs.devin.ai/onboard-devin/environment-yaml)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview)
- [GCP Identity-Aware Proxy](https://cloud.google.com/iap/docs/using-tcp-forwarding)
