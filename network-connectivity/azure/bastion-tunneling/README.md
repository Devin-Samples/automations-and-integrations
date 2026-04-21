# Azure Bastion Tunneling

> Planned — not yet implemented.

Secure tunnel access to Azure VMs using Azure Bastion's native tunneling feature — no public IPs on target VMs, identity-aware access via Azure AD.

## When to Use

- Devin needs to reach a **single service** running on an Azure VM inside a VNet
- You want identity-based access control (Azure AD / RBAC) instead of SSH keys
- You need an Azure-native equivalent of AWS SSM port forwarding

## Planned Components

- ARM / Bicep template for Azure Bastion (Standard SKU with tunneling)
- VNet with private subnets and NSGs
- Azure AD role assignments for tunnel access
- Devin environment integration (Azure CLI auth + `az network bastion tunnel`)

## Reference

- [Azure Bastion — Connect via tunnel](https://learn.microsoft.com/en-us/azure/bastion/connect-ip-address)
- [Azure Bastion Native Client](https://learn.microsoft.com/en-us/azure/bastion/connect-native-client-windows)
