# AWS Client VPN

Full subnet-level VPN access to private AWS resources via an AWS Client VPN endpoint. Use this when Devin needs to reach multiple services across a private subnet — no single-port limitations.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  OpenVPN client                                              │
│  Config from: downloaded client configuration                │
│  Routes: 10.0.0.0/16 → VPN tunnel                           │
│                                                               │
│  Any service in VPC ──► OpenVPN tunnel                       │
└──────────────┬───────────────────────────────────────────────┘
               │ (encrypted TLS 1.2+ tunnel)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  AWS VPC (10.0.0.0/16)                                        │
│                                                               │
│  ┌────────────────────────────┐                               │
│  │  Client VPN Endpoint        │                               │
│  │  Mutual TLS authentication  │                               │
│  │  CIDR: 172.16.0.0/16       │                               │
│  └──────────┬─────────────────┘                               │
│             │ (associated with target subnet)                 │
│  ┌──────────▼─────────────────┐    ┌──────────────────────┐  │
│  │  Private Subnet A           │    │  Private Subnet B     │  │
│  │  ├─ Application servers     │    │  ├─ RDS / Aurora      │  │
│  │  ├─ Artifactory             │    │  ├─ ElastiCache       │  │
│  │  └─ Internal APIs           │    │  └─ OpenSearch        │  │
│  └────────────────────────────┘    └──────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

1. An AWS Client VPN endpoint is created and associated with one or more private subnets in your VPC
2. **Mutual TLS** (mTLS) authentication uses a server certificate (issued by ACM) and a client certificate
3. An authorization rule controls which networks the VPN client can access
4. The client `.ovpn` configuration is downloaded and stored as a Devin Secret
5. At session start, Devin connects via OpenVPN, gaining full network access to the authorized VPC subnets
6. All traffic to the VPC CIDR is routed through the encrypted tunnel

## When to Use

- Devin needs access to **multiple private services** across a VPC (app servers + databases + internal APIs)
- You need full network-layer routing, not just single-port tunnels
- Your organization already uses AWS Client VPN for developer access
- [SSM Port Forwarding](../ssm-port-forwarding/) is too limited (single port, single instance)

## Prerequisites

- AWS CLI v2
- An AWS account with permissions to create Client VPN endpoints, ACM certificates, and security groups
- OpenVPN client (available on Devin's default image)
- A VPC with private subnets

## Quick Start

### 1. Generate Certificates

```bash
# Clone the easy-rsa tool
git clone https://github.com/OpenVPN/easy-rsa.git /tmp/easy-rsa
cd /tmp/easy-rsa/easyrsa3

# Initialize PKI
./easyrsa init-pki
./easyrsa build-ca nopass  # Common Name: DevinVPNCA

# Generate server certificate
./easyrsa build-server-full server nopass

# Generate client certificate
./easyrsa build-client-full devin-client nopass
```

### 2. Import Certificates to ACM

```bash
REGION="us-east-1"

# Import server certificate
SERVER_CERT_ARN=$(aws acm import-certificate \
  --certificate fileb:///tmp/easy-rsa/easyrsa3/pki/issued/server.crt \
  --private-key fileb:///tmp/easy-rsa/easyrsa3/pki/private/server.key \
  --certificate-chain fileb:///tmp/easy-rsa/easyrsa3/pki/ca.crt \
  --region $REGION \
  --query CertificateArn --output text)

# Import client root CA
CLIENT_CA_ARN=$(aws acm import-certificate \
  --certificate fileb:///tmp/easy-rsa/easyrsa3/pki/ca.crt \
  --private-key fileb:///tmp/easy-rsa/easyrsa3/pki/private/ca.key \
  --region $REGION \
  --query CertificateArn --output text)
```

### 3. Create the Client VPN Endpoint

```bash
VPC_ID="vpc-xxxxxxxx"
SUBNET_ID="subnet-xxxxxxxx"  # Private subnet to associate

# Create the endpoint
ENDPOINT_ID=$(aws ec2 create-client-vpn-endpoint \
  --client-cidr-block 172.16.0.0/16 \
  --server-certificate-arn $SERVER_CERT_ARN \
  --authentication-options "Type=certificate-authentication,MutualAuthentication={ClientRootCertificateChainArn=$CLIENT_CA_ARN}" \
  --connection-log-options "Enabled=false" \
  --vpc-id $VPC_ID \
  --vpn-port 443 \
  --transport-protocol udp \
  --split-tunnel \
  --region $REGION \
  --query ClientVpnEndpointId --output text)

echo "Client VPN Endpoint: $ENDPOINT_ID"

# Associate with a subnet
aws ec2 associate-client-vpn-target-network \
  --client-vpn-endpoint-id $ENDPOINT_ID \
  --subnet-id $SUBNET_ID \
  --region $REGION

# Authorize access to the VPC CIDR
aws ec2 authorize-client-vpn-ingress \
  --client-vpn-endpoint-id $ENDPOINT_ID \
  --target-network-cidr 10.0.0.0/16 \
  --authorize-all-groups \
  --region $REGION
```

> **Note:** Subnet association takes ~5 minutes. The endpoint status must be `available` before connecting.

### 4. Download and Configure the Client Profile

```bash
# Download the client configuration
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id $ENDPOINT_ID \
  --region $REGION \
  --output text > /tmp/devin-vpn.ovpn

# Embed the client certificate and key
cat >> /tmp/devin-vpn.ovpn <<EOF

<cert>
$(cat /tmp/easy-rsa/easyrsa3/pki/issued/devin-client.crt)
</cert>
<key>
$(cat /tmp/easy-rsa/easyrsa3/pki/private/devin-client.key)
</key>
EOF
```

### 5. Connect

```bash
sudo openvpn --config /tmp/devin-vpn.ovpn --daemon

# Verify — ping a resource in the VPC
ping -c 3 10.0.1.x
```

### 6. Teardown

```bash
# Disassociate subnet first
ASSOC_ID=$(aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id $ENDPOINT_ID \
  --region $REGION \
  --query 'ClientVpnTargetNetworks[0].AssociationId' --output text)

aws ec2 disassociate-client-vpn-target-network \
  --client-vpn-endpoint-id $ENDPOINT_ID \
  --association-id $ASSOC_ID \
  --region $REGION

# Delete the endpoint
aws ec2 delete-client-vpn-endpoint \
  --client-vpn-endpoint-id $ENDPOINT_ID \
  --region $REGION

# Clean up ACM certificates
aws acm delete-certificate --certificate-arn $SERVER_CERT_ARN --region $REGION
aws acm delete-certificate --certificate-arn $CLIENT_CA_ARN --region $REGION
```

## Devin Environment Integration

**`initialize`** (one-time — OpenVPN is typically pre-installed):

```bash
sudo apt-get update && sudo apt-get install -y openvpn
```

**Secrets** (stored in Devin settings):

| Secret Name | Value | Scope |
|---|---|---|
| `AWS_VPN_CONFIG` | Full contents of the `.ovpn` file (with embedded certs/keys) | org or repo |

**`maintenance`** (every session — establishes the VPN):

```bash
# Write VPN config
echo "$AWS_VPN_CONFIG" > /tmp/aws-vpn.ovpn

# Connect
sudo openvpn --config /tmp/aws-vpn.ovpn --daemon --log /tmp/openvpn.log
sleep 10  # Wait for tunnel to establish

# Verify
ping -c 1 10.0.1.x || echo "VPN tunnel may not be ready yet"
```

See also [Devin VPN Configuration](https://docs.devin.ai/onboard-devin/vpn) for Devin's built-in VPN support, which may simplify this setup.

## Cost (Estimates)

> Costs below are approximate estimates based on published cloud provider pricing at time of writing. Verify current pricing on the provider's pricing page before budgeting.

| Resource | Approximate Cost |
|---|---|
| Client VPN endpoint | ~$0.15/hr (~$108/month) |
| Client VPN connection | ~$0.05/hr per active connection |
| Data transfer | Standard AWS data transfer rates |
| **Total (1 connection)** | **~$0.20/hr** (~$144/month if left running) |

The endpoint charges apply even when no clients are connected. Consider:
- Delete the endpoint when not in active use
- For single-service access, [SSM Port Forwarding](../ssm-port-forwarding/) is significantly cheaper (~$0.05/hr)
- Enable **split tunnel** (configured above) to avoid routing all traffic through the VPN

## Reference

- [AWS Client VPN Administrator Guide](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html)
- [Mutual Authentication](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-authentication.html#mutual)
- [Client VPN Endpoints](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/cvpn-working-endpoints.html)
- [Client VPN Pricing](https://aws.amazon.com/vpn/pricing/)
