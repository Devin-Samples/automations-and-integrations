# Azure Network Connectivity Patterns

Patterns for connecting Devin to private resources in Azure VNets.

## Patterns

| Pattern | Directory | Description | Status |
|---|---|---|---|
| **Bastion Tunneling** | `bastion-tunneling/` | Native SSH/RDP tunneling through Azure Bastion — no public IPs on VMs | Planned |
| **Private Endpoints** | `private-endpoints/` | Private IP connectivity to Azure PaaS services (Key Vault, Storage, SQL) | Planned |
| **VPN Gateway** | `vpn-gateway/` | Point-to-site or site-to-site VPN for full subnet routing | Planned |

## Which Pattern?

- **Single VM** → Bastion Tunneling — simplest, identity-aware, no VM public IP
- **Azure PaaS service (SQL, Storage, Key Vault)** → Private Endpoints — private IP for managed services
- **Multiple services across a VNet** → VPN Gateway (P2S) — full subnet routing

## Reference

- [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview)
- [Azure Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Azure VPN Gateway](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways)
