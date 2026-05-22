# Azure Bastion Tunneling

Secure tunnel access to Azure VMs using Azure Bastion's native tunneling feature — no public IPs on target VMs, identity-aware access via Microsoft Entra ID (Azure AD).

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  Azure CLI + SSH                                             │
│  Service Principal: devin-bastion-tunnel                      │
│  (scoped to Bastion tunnel + VM read)                        │
│                                                               │
│  localhost:<port> ──► az network bastion tunnel               │
└──────────────┬───────────────────────────────────────────────┘
               │ (encrypted TLS channel via Bastion)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  Azure VNet                                                    │
│                                                               │
│  ┌─────────────────────┐    ┌────────────────────────────┐   │
│  │  AzureBastionSubnet  │    │  Private Subnet             │   │
│  │  (Standard SKU)      │    │  ┌────────────────────────┐ │   │
│  │                      │◄──►│  │  Target VM              │ │   │
│  │  Native client       │    │  │  (no public IP)          │ │   │
│  │  tunneling enabled   │    │  │                         │ │   │
│  └─────────────────────┘    │  │  Your private service   │ │   │
│                              │  │  or app :<port>          │ │   │
│                              │  └────────────────────────┘ │   │
│                              └────────────────────────────┘   │
│                                                               │
│  NSGs:                                                       │
│  ├─ Bastion NSG: required inbound/outbound per Azure docs    │
│  └─ VM NSG: app port from VNet CIDR only                     │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

1. Azure Bastion (Standard SKU) is deployed into a dedicated `AzureBastionSubnet` within your VNet
2. The target VM runs in a private subnet with **no public IP** — it is not reachable from the internet
3. Bastion's **native client tunneling** feature allows the Azure CLI to open a TCP tunnel from `localhost:<port>` to the VM's private IP
4. A service principal with scoped RBAC permissions authenticates via the Azure CLI
5. All traffic is encrypted end-to-end through the Bastion channel

## Resources Created

| Resource | Type | Purpose |
|---|---|---|
| Resource Group | `Microsoft.Resources/resourceGroups` | Container for all resources |
| VNet | `Microsoft.Network/virtualNetworks` | Isolated network with two subnets |
| AzureBastionSubnet | Subnet | Required dedicated subnet for Bastion |
| Private Subnet | Subnet | Hosts the target VM |
| Azure Bastion | `Microsoft.Network/bastionHosts` | Managed bastion service (Standard SKU) |
| Public IP (Bastion) | `Microsoft.Network/publicIPAddresses` | Required for Bastion — not on the VM |
| Bastion NSG | `Microsoft.Network/networkSecurityGroups` | Required inbound/outbound rules for Bastion |
| VM NSG | `Microsoft.Network/networkSecurityGroups` | App port from VNet CIDR only |
| Target VM | `Microsoft.Compute/virtualMachines` | Private VM hosting your service |
| NIC | `Microsoft.Network/networkInterfaces` | VM network interface (private IP only) |
| Service Principal | Microsoft Entra ID | Scoped RBAC for tunnel access |

## Prerequisites

- Azure CLI v2.50+
- An Azure subscription with permissions to create resource groups, VNets, VMs, and Bastion
- `az extension add --name bastion` (if not already installed)

## Quick Start

### 1. Deploy the Resources

```bash
# Variables
RESOURCE_GROUP="devin-bastion-tunnel"
LOCATION="eastus"
VNET_NAME="devin-vnet"
VM_NAME="devin-target-vm"
BASTION_NAME="devin-bastion"
ADMIN_USER="devinadmin"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create VNet with two subnets
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefix 10.0.0.0/16 \
  --subnet-name private-subnet \
  --subnet-prefix 10.0.1.0/24

# Create the AzureBastionSubnet (name is mandatory)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name AzureBastionSubnet \
  --address-prefix 10.0.0.0/26

# Create NSG for the VM subnet
az network nsg create \
  --resource-group $RESOURCE_GROUP \
  --name "${VM_NAME}-nsg"

az network nsg rule create \
  --resource-group $RESOURCE_GROUP \
  --nsg-name "${VM_NAME}-nsg" \
  --name AllowAppPortFromVNet \
  --priority 100 \
  --source-address-prefixes 10.0.0.0/16 \
  --destination-port-ranges 8081 \
  --access Allow \
  --protocol Tcp \
  --direction Inbound

# Associate NSG with private subnet
az network vnet subnet update \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name private-subnet \
  --network-security-group "${VM_NAME}-nsg"

# Create the target VM (no public IP)
az vm create \
  --resource-group $RESOURCE_GROUP \
  --name $VM_NAME \
  --image Ubuntu2204 \
  --size Standard_B1s \
  --vnet-name $VNET_NAME \
  --subnet private-subnet \
  --public-ip-address "" \
  --admin-username $ADMIN_USER \
  --generate-ssh-keys \
  --custom-data '#cloud-config
packages:
  - nginx
write_files:
  - path: /etc/nginx/sites-available/default
    content: |
      server {
        listen 8081;
        location /api/system/ping { return 200 "OK"; }
        location /api/system/version {
          return 200 "{\"version\":\"1.0.0\",\"service\":\"mock-private-endpoint\",\"status\":\"healthy\"}";
        }
        location /api/status {
          return 200 "{\"connected\":true,\"source\":\"bastion-tunneling\",\"network\":\"private-vnet\",\"ingress\":\"none\"}";
        }
      }
runcmd:
  - systemctl restart nginx'

# Create public IP for Bastion
az network public-ip create \
  --resource-group $RESOURCE_GROUP \
  --name "${BASTION_NAME}-pip" \
  --sku Standard \
  --allocation-method Static

# Deploy Azure Bastion (Standard SKU — required for native tunneling)
az network bastion create \
  --resource-group $RESOURCE_GROUP \
  --name $BASTION_NAME \
  --public-ip-address "${BASTION_NAME}-pip" \
  --vnet-name $VNET_NAME \
  --sku Standard \
  --enable-tunneling true
```

> **Note:** Bastion deployment takes ~5–10 minutes.

### 2. Create a Service Principal (Scoped)

```bash
# Get the resource IDs
BASTION_ID=$(az network bastion show --name $BASTION_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)
VM_ID=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

# Create a service principal with minimal scope
az ad sp create-for-rbac \
  --name "devin-bastion-tunnel" \
  --role "Reader" \
  --scopes $VM_ID

# Grant Bastion tunnel access
az role assignment create \
  --assignee <SERVICE_PRINCIPAL_APP_ID> \
  --role "Bastion Tunnel User" \
  --scope $BASTION_ID
```

> **Custom Role (optional):** If the built-in "Bastion Tunnel User" role is not available, create a custom role with `Microsoft.Network/bastionHosts/tunnelEndpoints/action`.

### 3. Establish the Tunnel

```bash
# Authenticate as the service principal
az login --service-principal \
  -u <APP_ID> \
  -p <CLIENT_SECRET> \
  --tenant <TENANT_ID>

# Get the target VM resource ID
TARGET_VM_ID=$(az vm show --name $VM_NAME --resource-group $RESOURCE_GROUP --query id -o tsv)

# Start the tunnel
az network bastion tunnel \
  --name $BASTION_NAME \
  --resource-group $RESOURCE_GROUP \
  --target-resource-id $TARGET_VM_ID \
  --resource-port 8081 \
  --port 8081
```

### 4. Verify Connectivity

In a separate terminal:

```bash
# Health check
curl -s http://localhost:8081/api/system/ping
# → OK

# Service version
curl -s http://localhost:8081/api/system/version | jq
# → {"version":"1.0.0","service":"mock-private-endpoint","status":"healthy"}
```

### 5. Teardown

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## Devin Environment Integration

Add to your Devin environment configuration to establish connectivity at session start:

**`initialize`** (one-time — installs Azure CLI and Bastion extension):

```bash
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
az extension add --name bastion --yes 2>/dev/null || true
```

**Secrets** (stored in Devin settings):

| Secret Name | Value | Scope |
|---|---|---|
| `AZURE_BASTION_SP_ID` | Service principal app ID | org or repo |
| `AZURE_BASTION_SP_SECRET` | Service principal client secret | org or repo |
| `AZURE_BASTION_TENANT_ID` | Azure AD tenant ID | org or repo |

**`maintenance`** (every session — authenticates and establishes the tunnel):

```bash
# Authenticate
az login --service-principal \
  -u "$AZURE_BASTION_SP_ID" \
  -p "$AZURE_BASTION_SP_SECRET" \
  --tenant "$AZURE_BASTION_TENANT_ID" --output none

# Establish tunnel in background
az network bastion tunnel \
  --name <BASTION_NAME> \
  --resource-group <RESOURCE_GROUP> \
  --target-resource-id <TARGET_VM_RESOURCE_ID> \
  --resource-port 8081 \
  --port 8081 &
```

## Cost

| Resource | Approximate Cost |
|---|---|
| Azure Bastion (Standard) | ~$0.19/hr (~$137/month) |
| VM (Standard_B1s) | ~$0.01/hr |
| Public IP (Bastion) | ~$0.005/hr |
| **Total** | **~$0.21/hr** (~$150/month if left running) |

Tear down the resource group when not in use to avoid charges. Bastion is the primary cost driver.

## Reference

- [Azure Bastion — Connect via tunnel](https://learn.microsoft.com/en-us/azure/bastion/connect-ip-address)
- [Azure Bastion Native Client](https://learn.microsoft.com/en-us/azure/bastion/connect-native-client-windows)
- [Bastion SKU comparison](https://learn.microsoft.com/en-us/azure/bastion/configuration-settings#skus)
- [az network bastion tunnel](https://learn.microsoft.com/en-us/cli/azure/network/bastion?view=azure-cli-latest#az-network-bastion-tunnel)
