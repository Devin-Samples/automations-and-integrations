# Azure VPN Gateway

Point-to-site (P2S) or site-to-site (S2S) VPN connectivity for full subnet-level routing into Azure VNets. Use this when Devin needs to reach multiple private services across a VNet.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  OpenVPN client                                              │
│  Config from: downloaded VPN client profile                  │
│  Routes: 10.0.0.0/16 → VPN tunnel                           │
│                                                               │
│  Any service in VNet ──► OpenVPN tunnel                      │
└──────────────┬───────────────────────────────────────────────┘
               │ (encrypted TLS 1.2+ tunnel)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  Azure VNet (10.0.0.0/16)                                     │
│                                                               │
│  ┌─────────────────────────┐                                 │
│  │  GatewaySubnet           │                                 │
│  │  VPN Gateway (VpnGw1)   │                                 │
│  │  P2S: OpenVPN + certs    │                                 │
│  └──────────┬──────────────┘                                 │
│             │                                                │
│  ┌──────────▼──────────────┐    ┌────────────────────────┐   │
│  │  Subnet A                │    │  Subnet B               │   │
│  │  ├─ App Server           │    │  ├─ Database             │   │
│  │  ├─ Artifactory          │    │  ├─ Redis                │   │
│  │  └─ Internal APIs        │    │  └─ Monitoring           │   │
│  └─────────────────────────┘    └────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

1. An Azure VPN Gateway is deployed into a dedicated `GatewaySubnet` within your VNet
2. Point-to-site (P2S) configuration uses **OpenVPN protocol** with certificate-based authentication
3. The VPN client profile (`.ovpn` file) is downloaded and stored as a Devin Secret
4. At session start, Devin connects via OpenVPN, gaining full network access to the VNet's address space
5. All traffic to the VNet CIDR is routed through the encrypted tunnel

## When to Use

- Devin needs access to **multiple private services** across an Azure VNet (app servers + databases + internal APIs)
- You need full network-layer routing, not just single-port tunnels
- Your organization already uses Azure VPN Gateway for developer access
- You need to reach services that don't support Bastion tunneling (non-VM resources on the network)

## Prerequisites

- Azure CLI v2.50+
- An Azure subscription with permissions to create VPN Gateways
- OpenVPN client (available on Devin's default image)
- `openssl` for certificate generation

## Quick Start

### 1. Create the VNet and Gateway Subnet

```bash
# Variables
RESOURCE_GROUP="devin-vpn-gateway"
LOCATION="eastus"
VNET_NAME="devin-vnet"
GW_NAME="devin-vpn-gw"

# Create resource group
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create VNet with application subnet
az network vnet create \
  --resource-group $RESOURCE_GROUP \
  --name $VNET_NAME \
  --address-prefix 10.0.0.0/16 \
  --subnet-name app-subnet \
  --subnet-prefix 10.0.1.0/24

# Create the GatewaySubnet (name is mandatory)
az network vnet subnet create \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name GatewaySubnet \
  --address-prefix 10.0.255.0/27
```

### 2. Generate Certificates

```bash
# Generate root CA
openssl req -x509 -new -nodes \
  -keyout /tmp/vpn-ca.key \
  -out /tmp/vpn-ca.crt \
  -days 3650 \
  -subj "/CN=DevinVPNRootCA"

# Generate client certificate
openssl req -new -nodes \
  -keyout /tmp/vpn-client.key \
  -out /tmp/vpn-client.csr \
  -subj "/CN=DevinVPNClient"

openssl x509 -req \
  -in /tmp/vpn-client.csr \
  -CA /tmp/vpn-ca.crt \
  -CAkey /tmp/vpn-ca.key \
  -CAcreateserial \
  -out /tmp/vpn-client.crt \
  -days 365

# Extract root cert data for Azure (base64, no headers)
ROOT_CERT_DATA=$(openssl x509 -in /tmp/vpn-ca.crt -outform der | base64 -w0)
```

### 3. Deploy the VPN Gateway

```bash
# Create public IP for the gateway
az network public-ip create \
  --resource-group $RESOURCE_GROUP \
  --name "${GW_NAME}-pip" \
  --allocation-method Static \
  --sku Standard

# Create the VPN gateway (~30-45 minutes)
az network vnet-gateway create \
  --resource-group $RESOURCE_GROUP \
  --name $GW_NAME \
  --vnet $VNET_NAME \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --public-ip-address "${GW_NAME}-pip" \
  --client-protocol OpenVPN \
  --address-prefixes 172.16.0.0/24

# Upload root certificate
az network vnet-gateway root-cert create \
  --resource-group $RESOURCE_GROUP \
  --gateway-name $GW_NAME \
  --name "DevinRootCA" \
  --public-cert-data "$ROOT_CERT_DATA"
```

> **Note:** VPN Gateway creation takes 30–45 minutes.

### 4. Download and Configure the VPN Profile

```bash
# Generate VPN client configuration
az network vnet-gateway vpn-client generate \
  --resource-group $RESOURCE_GROUP \
  --name $GW_NAME \
  --authentication-method EAPTLS

# Download the profile URL
PROFILE_URL=$(az network vnet-gateway vpn-client show-url \
  --resource-group $RESOURCE_GROUP \
  --name $GW_NAME \
  --output tsv)

# Download and extract
curl -o /tmp/vpn-profile.zip "$PROFILE_URL"
unzip /tmp/vpn-profile.zip -d /tmp/vpn-profile/

# The OpenVPN profile is at /tmp/vpn-profile/OpenVPN/vpnconfig.ovpn
# Embed the client cert and key into the profile
cat >> /tmp/vpn-profile/OpenVPN/vpnconfig.ovpn <<EOF

<cert>
$(cat /tmp/vpn-client.crt)
</cert>
<key>
$(cat /tmp/vpn-client.key)
</key>
EOF
```

### 5. Connect

```bash
sudo openvpn --config /tmp/vpn-profile/OpenVPN/vpnconfig.ovpn --daemon

# Verify — ping a resource in the VNet
ping -c 3 10.0.1.x
```

### 6. Teardown

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## Devin Environment Integration

**`initialize`** (one-time — OpenVPN is typically pre-installed):

```bash
sudo apt-get update && sudo apt-get install -y openvpn
```

**Secrets** (stored in Devin settings):

| Secret Name | Value | Scope |
|---|---|---|
| `AZURE_VPN_CONFIG` | Full contents of the `.ovpn` file (with embedded certs/keys) | org or repo |

**`maintenance`** (every session — establishes the VPN):

```bash
# Write VPN config
echo "$AZURE_VPN_CONFIG" > /tmp/azure-vpn.ovpn

# Connect
sudo openvpn --config /tmp/azure-vpn.ovpn --daemon --log /tmp/openvpn.log
sleep 10  # Wait for tunnel to establish

# Verify
ping -c 1 10.0.1.x || echo "VPN tunnel may not be ready yet"
```

See also [Devin VPN Configuration](https://docs.devin.ai/onboard-devin/vpn) for Devin's built-in VPN support.

## Cost (Estimates)

> Costs below are approximate estimates based on published cloud provider pricing at time of writing. Verify current pricing on the provider's pricing page before budgeting.

| Resource | Approximate Cost |
|---|---|
| VPN Gateway (VpnGw1) | ~$0.19/hr (~$140/month) |
| Public IP (Standard) | ~$0.005/hr |
| Data transfer | ~$0.035/GB outbound |
| **Total** | **~$0.19/hr** (~$140/month if left running) |

The VPN Gateway is the primary cost driver. Consider:
- Use `VpnGw1` (smallest SKU) unless you need higher throughput
- Deallocate the gateway when not in active use (takes 30+ min to recreate)
- For cost-sensitive scenarios, consider [Bastion Tunneling](../bastion-tunneling/) for single-service access

## Reference

- [Azure VPN Gateway](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways)
- [Point-to-Site Configuration](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-point-to-site-resource-manager-portal)
- [OpenVPN Protocol on Azure](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-openvpn)
- [P2S Certificate Authentication](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-point-to-site-resource-manager-portal)
