# Azure Network Connectivity Patterns

Patterns for connecting Devin to private resources in Azure VNets.

## Patterns

| Pattern | Directory | Description | Status |
|---|---|---|---|
| **Bastion Tunneling** | [`bastion-tunneling/`](bastion-tunneling/) | Native SSH/RDP tunneling through Azure Bastion — no public IPs on VMs, identity-aware | Available |
| **Private Endpoints** | [`private-endpoints/`](private-endpoints/) | Private IP connectivity to Azure PaaS services (Key Vault, Storage, SQL, Cosmos DB) | Available |
| **VPN Gateway** | [`vpn-gateway/`](vpn-gateway/) | Point-to-site or site-to-site VPN for full subnet routing via OpenVPN | Available |

## Which Pattern?

- **Single VM** → [Bastion Tunneling](bastion-tunneling/) — simplest, identity-aware, no VM public IP
- **Azure PaaS service (SQL, Storage, Key Vault)** → [Private Endpoints](private-endpoints/) — private IP for managed services
- **Multiple services across a VNet** → [VPN Gateway (P2S)](vpn-gateway/) — full subnet routing

## Combining Patterns

Private Endpoints provide the network path to PaaS services but require Devin to be inside the VNet. Pair them with:
- **Bastion Tunneling** for quick, single-service access to VMs that can reach the private endpoints
- **VPN Gateway** for full VNet access including private endpoint DNS resolution

## Reference

- [Azure Bastion](https://learn.microsoft.com/en-us/azure/bastion/bastion-overview)
- [Azure Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Azure VPN Gateway](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways)
