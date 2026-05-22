# GCP IAP Tunneling

Secure tunnel access to GCP VMs using Identity-Aware Proxy (IAP) TCP forwarding — no public IPs, IAM-based access control, free.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  gcloud CLI                                                  │
│  Service Account: devin-iap-tunnel@<project>.iam             │
│  (scoped to IAP tunnel + compute.viewer)                     │
│                                                               │
│  localhost:<port> ──► gcloud compute start-iap-tunnel         │
└──────────────┬───────────────────────────────────────────────┘
               │ (encrypted TLS channel via IAP)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  GCP VPC                                                       │
│                                                               │
│  ┌─────────────────────────────┐                              │
│  │  Private Subnet              │                              │
│  │  ┌─────────────────────────┐ │                              │
│  │  │  Target VM               │ │                              │
│  │  │  (no external IP)        │ │                              │
│  │  │                          │ │                              │
│  │  │  Your private service    │ │                              │
│  │  │  or app :<port>          │ │                              │
│  │  └─────────────────────────┘ │                              │
│  └─────────────────────────────┘                              │
│                                                               │
│  Firewall Rules:                                             │
│  ├─ Allow IAP range (35.235.240.0/20) to target port         │
│  └─ Deny all other ingress from internet                     │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

1. The target VM runs in a private subnet with **no external IP** — it is not reachable from the internet
2. IAP acts as a managed reverse proxy, authenticating users via Google IAM before forwarding TCP traffic
3. A firewall rule allows ingress **only from Google's IAP IP range** (`35.235.240.0/20`) to the target port
4. A dedicated service account with scoped IAM bindings authenticates via `gcloud`
5. The `gcloud compute start-iap-tunnel` command establishes an encrypted tunnel mapping `localhost:<port>` to the VM's internal port
6. IAP TCP forwarding is **free** — no per-hour charges for the tunnel itself

## Resources Created

| Resource | Type | Purpose |
|---|---|---|
| VPC Network | `google_compute_network` | Isolated network |
| Private Subnet | `google_compute_subnetwork` | Hosts the target VM |
| Firewall Rule (IAP) | `google_compute_firewall` | Allow IAP range to target port |
| Firewall Rule (deny-all) | `google_compute_firewall` | Block all other ingress |
| Cloud Router + NAT | `google_compute_router` / `google_compute_router_nat` | Outbound-only internet for package installs |
| Target VM | `google_compute_instance` | Private VM hosting your service |
| Service Account | `google_service_account` | Scoped IAM for tunnel access |
| IAM Bindings | `google_project_iam_member` | `iap.tunnelResourceAccessor` + `compute.viewer` |

## Prerequisites

- `gcloud` CLI
- A GCP project with billing enabled
- Permissions to create VMs, firewall rules, and IAM bindings
- IAP API enabled: `gcloud services enable iap.googleapis.com`

## Quick Start

### 1. Set Up the Environment

```bash
# Variables
PROJECT_ID="your-gcp-project"
REGION="us-central1"
ZONE="us-central1-a"
NETWORK_NAME="devin-iap-network"
SUBNET_NAME="devin-private-subnet"
VM_NAME="devin-target-vm"
SA_NAME="devin-iap-tunnel"
TARGET_PORT=8081

gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable compute.googleapis.com iap.googleapis.com
```

### 2. Create the Network and Firewall Rules

```bash
# Create VPC network
gcloud compute networks create $NETWORK_NAME \
  --subnet-mode=custom

# Create private subnet
gcloud compute networks subnets create $SUBNET_NAME \
  --network=$NETWORK_NAME \
  --range=10.0.1.0/24 \
  --region=$REGION

# Allow IAP TCP forwarding to the target port
gcloud compute firewall-rules create allow-iap-tunnel \
  --network=$NETWORK_NAME \
  --allow=tcp:$TARGET_PORT \
  --source-ranges=35.235.240.0/20 \
  --description="Allow IAP TCP forwarding to target port"

# Deny all other ingress (lower priority)
gcloud compute firewall-rules create deny-all-ingress \
  --network=$NETWORK_NAME \
  --action=DENY \
  --rules=all \
  --source-ranges=0.0.0.0/0 \
  --priority=65534 \
  --description="Deny all ingress from internet"

# Cloud Router + NAT for outbound-only internet (package installs)
gcloud compute routers create devin-router \
  --network=$NETWORK_NAME \
  --region=$REGION

gcloud compute routers nats create devin-nat \
  --router=devin-router \
  --region=$REGION \
  --auto-allocate-nat-external-ips \
  --nat-all-subnet-ip-ranges
```

### 3. Create the Target VM

```bash
gcloud compute instances create $VM_NAME \
  --zone=$ZONE \
  --machine-type=e2-micro \
  --subnet=$SUBNET_NAME \
  --no-address \
  --metadata=startup-script='#!/bin/bash
apt-get update && apt-get install -y nginx
cat > /etc/nginx/sites-available/default <<EOF
server {
  listen 8081;
  location /api/system/ping { return 200 "OK"; }
  location /api/system/version {
    return 200 "{\"version\":\"1.0.0\",\"service\":\"mock-private-endpoint\",\"status\":\"healthy\"}";
  }
  location /api/status {
    return 200 "{\"connected\":true,\"source\":\"iap-tunneling\",\"network\":\"private-vpc\",\"ingress\":\"none\"}";
  }
}
EOF
systemctl restart nginx'
```

### 4. Create a Service Account with Scoped IAM

```bash
# Create the service account
gcloud iam service-accounts create $SA_NAME \
  --display-name="Devin IAP Tunnel Access"

SA_EMAIL="${SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

# Grant IAP tunnel access
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/iap.tunnelResourceAccessor"

# Grant minimal compute viewer (needed to resolve instance)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SA_EMAIL}" \
  --role="roles/compute.viewer"

# Create and download a key
gcloud iam service-accounts keys create /tmp/devin-iap-sa-key.json \
  --iam-account=$SA_EMAIL
```

### 5. Establish the Tunnel

```bash
# Authenticate as the service account
gcloud auth activate-service-account --key-file=/tmp/devin-iap-sa-key.json

# Start the IAP tunnel
gcloud compute start-iap-tunnel $VM_NAME $TARGET_PORT \
  --local-host-port=localhost:$TARGET_PORT \
  --zone=$ZONE
```

### 6. Verify Connectivity

In a separate terminal:

```bash
# Health check
curl -s http://localhost:8081/api/system/ping
# → OK

# Service version
curl -s http://localhost:8081/api/system/version | jq
# → {"version":"1.0.0","service":"mock-private-endpoint","status":"healthy"}
```

### 7. Teardown

```bash
gcloud compute instances delete $VM_NAME --zone=$ZONE --quiet
gcloud compute firewall-rules delete allow-iap-tunnel deny-all-ingress --quiet
gcloud compute routers nats delete devin-nat --router=devin-router --region=$REGION --quiet
gcloud compute routers delete devin-router --region=$REGION --quiet
gcloud compute networks subnets delete $SUBNET_NAME --region=$REGION --quiet
gcloud compute networks delete $NETWORK_NAME --quiet
gcloud iam service-accounts delete $SA_EMAIL --quiet
```

## Devin Environment Integration

Add to your Devin environment configuration to establish connectivity at session start:

**`initialize`** (one-time — installs gcloud CLI):

```bash
# gcloud is pre-installed on most Devin images; if not:
curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/opt
ln -sf /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud
ln -sf /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil
```

**Secrets** (stored in Devin settings):

| Secret Name | Value | Scope |
|---|---|---|
| `GCP_IAP_SA_KEY` | Contents of the service account JSON key file | org or repo |

**`maintenance`** (every session — authenticates and establishes the tunnel):

```bash
# Write the service account key
echo "$GCP_IAP_SA_KEY" > /tmp/gcp-iap-sa-key.json

# Authenticate
gcloud auth activate-service-account --key-file=/tmp/gcp-iap-sa-key.json
gcloud config set project <PROJECT_ID>

# Establish IAP tunnel in background
gcloud compute start-iap-tunnel <VM_NAME> 8081 \
  --local-host-port=localhost:8081 \
  --zone=<ZONE> &
sleep 5  # Wait for tunnel to establish
```

## Cost

| Resource | Approximate Cost |
|---|---|
| IAP TCP forwarding | **Free** |
| VM (e2-micro) | ~$0.008/hr (~$6/month) |
| Cloud NAT | ~$0.045/hr + data |
| **Total** | **~$0.05/hr** (~$38/month if left running) |

IAP tunneling itself is free. The primary costs are the VM and Cloud NAT (needed for outbound package installs). Tear down resources when not in use.

## Reference

- [IAP TCP Forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [IAP Firewall Rules](https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule)
- [gcloud compute start-iap-tunnel](https://cloud.google.com/sdk/gcloud/reference/compute/start-iap-tunnel)
- [Service Account Keys](https://cloud.google.com/iam/docs/creating-managing-service-account-keys)
