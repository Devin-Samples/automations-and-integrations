# Azure Private Endpoints

> Planned — not yet implemented.

Private IP connectivity to Azure PaaS services (Key Vault, Storage, SQL Database) without exposing them to the public internet.

## When to Use

- Devin needs to access an **Azure managed service** over a private IP
- You want to disable public access to a PaaS resource entirely
- You need DNS resolution to route service traffic through the VNet

## Planned Components

- ARM / Bicep template for Private Endpoints and Private DNS Zones
- VNet integration and NSG configuration
- Devin environment integration

## Reference

- [Azure Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Private DNS Zone Integration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
