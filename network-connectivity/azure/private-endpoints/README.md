# Azure Private Endpoints

Private IP connectivity to Azure PaaS services (SQL Database, Key Vault, Storage, Cosmos DB) without exposing them to the public internet. Traffic stays on the Microsoft backbone.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  Application / CLI / MCP Server                              │
│  Connects to: <service>.privatelink.<zone>                   │
│  Resolves to: 10.0.2.x (private IP)                          │
│                                                               │
└──────────────┬───────────────────────────────────────────────┘
               │ (via VPN or Bastion tunnel to the VNet)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  Azure VNet                                                    │
│                                                               │
│  ┌────────────────────────────┐                               │
│  │  Private Endpoint Subnet    │                               │
│  │  ┌────────────────────────┐ │                               │
│  │  │  Private Endpoint       │ │   ┌──────────────────────┐  │
│  │  │  NIC: 10.0.2.x         │─┼──►│  Azure PaaS Service  │  │
│  │  │                         │ │   │  (SQL, Storage, etc.) │  │
│  │  └────────────────────────┘ │   │  Public access: OFF    │  │
│  └────────────────────────────┘   └──────────────────────────┘  │
│                                                               │
│  Private DNS Zone:                                           │
│  <service>.privatelink.database.windows.net → 10.0.2.x       │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

1. A **Private Endpoint** creates a network interface with a private IP inside your VNet, mapped to a specific Azure PaaS resource
2. A **Private DNS Zone** resolves the service's FQDN to the private IP instead of the public IP
3. The PaaS service's **public access is disabled** — it is only reachable via the private endpoint
4. Devin reaches the private endpoint through a VPN or Bastion tunnel into the VNet
5. All traffic stays on the Microsoft backbone — never traverses the public internet

## When to Use

- Devin needs to access an **Azure managed service** (SQL Database, Key Vault, Storage, Cosmos DB, etc.) over a private IP
- You want to **disable public access** to the PaaS resource entirely
- You need DNS resolution to route service traffic through the VNet
- You already have (or plan to set up) VPN or tunnel connectivity into the VNet

> **Note:** Private Endpoints provide the network path. Devin still needs a way to reach the VNet — typically via [Bastion Tunneling](../bastion-tunneling/) for a single service or [VPN Gateway](../vpn-gateway/) for multiple services.

## Supported Services

| Service | Private Link Zone | Example FQDN |
|---|---|---|
| Azure SQL Database | `privatelink.database.windows.net` | `myserver.privatelink.database.windows.net` |
| Azure Cosmos DB | `privatelink.documents.azure.com` | `myaccount.privatelink.documents.azure.com` |
| Azure Key Vault | `privatelink.vaultcore.azure.net` | `myvault.privatelink.vaultcore.azure.net` |
| Storage (Blob) | `privatelink.blob.core.windows.net` | `mystorage.privatelink.blob.core.windows.net` |
| Storage (Table) | `privatelink.table.core.windows.net` | `mystorage.privatelink.table.core.windows.net` |
| Azure Cache for Redis | `privatelink.redis.cache.windows.net` | `myredis.privatelink.redis.cache.windows.net` |

See the [full list](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns#azure-services-dns-zone-configuration) for all supported services.

## Quick Start

This example creates a Private Endpoint for an Azure SQL Database.

### Prerequisites

- Azure CLI v2.50+
- An existing Azure SQL Server (or substitute your target PaaS service)
- A VNet where the private endpoint will be created

### 1. Create the Private Endpoint

```bash
# Variables
RESOURCE_GROUP="devin-private-endpoints"
LOCATION="eastus"
VNET_NAME="devin-vnet"
PE_SUBNET_NAME="pe-subnet"
SQL_SERVER_NAME="your-sql-server"
SQL_SERVER_RG="your-sql-server-rg"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create VNet (or use existing)
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefix 10.0.0.0/16 \
  --subnet-name $PE_SUBNET_NAME \
  --subnet-prefix 10.0.2.0/24

# Disable private endpoint network policies on the subnet
az network vnet subnet update \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name $PE_SUBNET_NAME \
  --disable-private-endpoint-network-policies true

# Get the SQL Server resource ID
SQL_SERVER_ID=$(az sql server show \
  --name $SQL_SERVER_NAME \
  --resource-group $SQL_SERVER_RG \
  --query id -o tsv)

# Create the private endpoint
az network private-endpoint create \
  --resource-group $RESOURCE_GROUP \
  --name "${SQL_SERVER_NAME}-pe" \
  --vnet-name $VNET_NAME \
  --subnet $PE_SUBNET_NAME \
  --private-connection-resource-id $SQL_SERVER_ID \
  --group-id sqlServer \
  --connection-name "${SQL_SERVER_NAME}-connection"
```

### 2. Configure Private DNS

```bash
# Create private DNS zone
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name "privatelink.database.windows.net"

# Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "privatelink.database.windows.net" \
  --name "${VNET_NAME}-dns-link" \
  --virtual-network $VNET_NAME \
  --registration-enabled false

# Create DNS zone group (auto-registers DNS records)
az network private-endpoint dns-zone-group create \
  --resource-group $RESOURCE_GROUP \
  --endpoint-name "${SQL_SERVER_NAME}-pe" \
  --name "default" \
  --private-dns-zone "privatelink.database.windows.net" \
  --zone-name "sqlServer"
```

### 3. Disable Public Access

```bash
az sql server update \
  --name $SQL_SERVER_NAME \
  --resource-group $SQL_SERVER_RG \
  --public-network-access Disabled
```

### 4. Verify

From a VM or tunnel within the VNet:

```bash
# DNS resolution should return the private IP
nslookup ${SQL_SERVER_NAME}.database.windows.net
# → 10.0.2.x

# Test connection (requires sqlcmd or similar)
sqlcmd -S ${SQL_SERVER_NAME}.database.windows.net -U <user> -P <password> -Q "SELECT 1"
```

### 5. Teardown

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
# Re-enable public access on the SQL server if needed
az sql server update \
  --name $SQL_SERVER_NAME \
  --resource-group $SQL_SERVER_RG \
  --public-network-access Enabled
```

## Devin Environment Integration

Private Endpoints require Devin to be **inside the VNet** to resolve the private DNS. Pair this with [Bastion Tunneling](../bastion-tunneling/) or [VPN Gateway](../vpn-gateway/).

For database access specifically, see the [Database Access guide](../../database-access/) for MCP and CLI configuration. The connection string uses the same FQDN — DNS resolution handles routing to the private IP.

**Example — Azure SQL via MCP with Private Endpoint:**

1. Set up VPN or Bastion tunnel to the VNet (see respective guides)
2. Store the connection string as a Devin Secret:
   ```
   Server=tcp:myserver.database.windows.net,1433;Database=mydb;User ID=devin_readonly;Password=SECRET;Encrypt=True;
   ```
3. Enable the SQL Server MCP in Settings > MCP Marketplace

## Cost

| Resource | Approximate Cost |
|---|---|
| Private Endpoint | ~$0.01/hr (~$7.30/month) |
| Data processed | ~$0.01/GB |
| Private DNS Zone | ~$0.50/month |
| **Total** | **~$8/month** + data charges |

## Reference

- [Azure Private Endpoints](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-overview)
- [Private Endpoint DNS Configuration](https://learn.microsoft.com/en-us/azure/private-link/private-endpoint-dns)
- [Disable Public Access (SQL)](https://learn.microsoft.com/en-us/azure/azure-sql/database/connectivity-settings#deny-public-network-access)
- [Supported Services](https://learn.microsoft.com/en-us/azure/private-link/private-link-service-overview)
