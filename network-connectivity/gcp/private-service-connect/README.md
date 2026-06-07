# GCP Private Service Connect

Private IP connectivity to Google APIs, Google-managed services, and your own services — traffic stays on Google's network backbone. No public internet exposure.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  Application / CLI / MCP Server                              │
│  Connects to: private endpoint IP or custom DNS              │
│                                                               │
└──────────────┬───────────────────────────────────────────────┘
               │ (via IAP tunnel or VPN into VPC)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  GCP VPC                                                       │
│                                                               │
│  ┌────────────────────────────┐                               │
│  │  Private Subnet             │                               │
│  │  ┌────────────────────────┐ │                               │
│  │  │  PSC Endpoint           │ │   ┌──────────────────────┐  │
│  │  │  Forwarding Rule:      │─┼──►│  Google API / Service │  │
│  │  │  10.0.2.x              │ │   │  (Cloud SQL, GCS,     │  │
│  │  │                         │ │   │   Vertex AI, etc.)    │  │
│  │  └────────────────────────┘ │   └──────────────────────┘  │
│  └────────────────────────────┘                               │
│                                                               │
│  OR: Published Service (your own ILB-backed service)          │
│  ┌────────────────────────────┐                               │
│  │  Service Attachment         │                               │
│  │  (backed by ILB)           │──► Your private microservice  │
│  └────────────────────────────┘                               │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

### Accessing Google APIs

1. A **PSC endpoint** creates a forwarding rule with a private IP in your VPC
2. DNS is configured to resolve Google API FQDNs (e.g., `storage.googleapis.com`) to the private IP
3. All traffic to Google APIs flows through the private endpoint instead of the public internet
4. No firewall rules or NAT needed for Google API access

### Accessing Published Services (Your Own or Third-Party)

1. A service producer publishes their service via a **Service Attachment** backed by an Internal Load Balancer (ILB)
2. A consumer creates a **PSC endpoint** in their VPC pointing to the Service Attachment
3. Traffic flows: Consumer VPC → PSC Endpoint → Service Attachment → ILB → Producer Service

## When to Use

- Devin needs to access **Google managed services** (Cloud SQL, GCS, BigQuery, Vertex AI, etc.) over a private IP
- You want to consume a third-party service published via Private Service Connect
- You need to keep all traffic on Google's network backbone for compliance
- You want to eliminate the need for Cloud NAT or external IPs for Google API access

## Supported Google APIs

PSC supports two bundles of Google APIs:

| Bundle | Endpoint Target | APIs Included |
|---|---|---|
| `all-apis` | `all-apis` | All Google APIs (BigQuery, Cloud SQL Admin, GCS, Vertex AI, etc.) |
| `vpc-sc` | `vpc-sc` | APIs compatible with VPC Service Controls |

For individual services published via Service Attachments, see [Published Services](https://cloud.google.com/vpc/docs/private-service-connect#published-services).

## Prerequisites

- `gcloud` CLI
- A GCP project with billing enabled
- A VPC network
- Permissions to create forwarding rules, addresses, and DNS records

## Quick Start: PSC for Google APIs

### 1. Reserve a Private IP

```bash
# Variables
PROJECT_ID="your-gcp-project"
NETWORK_NAME="devin-network"
REGION="us-central1"

gcloud config set project $PROJECT_ID

# Reserve a static internal IP for the PSC endpoint
gcloud compute addresses create psc-google-apis \
  --global \
  --purpose=PRIVATE_SERVICE_CONNECT \
  --addresses=10.0.100.1 \
  --network=$NETWORK_NAME
```

### 2. Create the PSC Endpoint

```bash
# Create forwarding rule for all Google APIs
gcloud compute forwarding-rules create psc-google-apis-rule \
  --global \
  --network=$NETWORK_NAME \
  --address=psc-google-apis \
  --target-google-apis-bundle=all-apis
```

### 3. Configure DNS

```bash
# Create a private DNS zone to override Google API resolution
gcloud dns managed-zones create google-apis-private \
  --dns-name="googleapis.com." \
  --visibility=private \
  --networks=$NETWORK_NAME \
  --description="Route Google API traffic through PSC"

# Add DNS records pointing to the PSC endpoint IP
gcloud dns record-sets create "*.googleapis.com." \
  --zone=google-apis-private \
  --type=A \
  --ttl=300 \
  --rrdatas=10.0.100.1
```

### 4. Verify

From a VM inside the VPC:

```bash
# DNS should resolve to the PSC endpoint IP
nslookup storage.googleapis.com
# → 10.0.100.1

# Access GCS via the private path
gsutil ls gs://your-bucket/
```

### 5. Teardown

```bash
gcloud dns record-sets delete "*.googleapis.com." --zone=google-apis-private --type=A --quiet
gcloud dns managed-zones delete google-apis-private --quiet
gcloud compute forwarding-rules delete psc-google-apis-rule --global --quiet
gcloud compute addresses delete psc-google-apis --global --quiet
```

## Quick Start: PSC for Published Services (Cloud SQL Example)

Cloud SQL supports PSC natively. This creates a private endpoint for a Cloud SQL instance.

### 1. Enable PSC on the Cloud SQL Instance

```bash
# Get the PSC service attachment URI
PSC_ATTACHMENT=$(gcloud sql instances describe your-sql-instance \
  --format="value(pscServiceAttachmentLink)")

echo "Service Attachment: $PSC_ATTACHMENT"
```

### 2. Create the PSC Endpoint

```bash
# Reserve IP
gcloud compute addresses create psc-cloud-sql \
  --region=$REGION \
  --subnet=your-private-subnet \
  --addresses=10.0.1.100

# Create forwarding rule
gcloud compute forwarding-rules create psc-cloud-sql-rule \
  --region=$REGION \
  --network=$NETWORK_NAME \
  --address=psc-cloud-sql \
  --target-service-attachment=$PSC_ATTACHMENT
```

### 3. Connect

```bash
# Connect using the private IP
psql "host=10.0.1.100 port=5432 dbname=mydb user=devin_readonly sslmode=require"
```

## Devin Environment Integration

PSC endpoints require Devin to be **inside the VPC** to use the private DNS resolution. Pair this with [IAP Tunneling](../iap-tunneling/) for single-service access.

For database access specifically, see the [Database Access guide](../../database-access/) for MCP and CLI configuration.

**Example — Cloud SQL via PSC:**

1. Set up IAP tunnel to a VM in the VPC (see [IAP Tunneling](../iap-tunneling/))
2. Forward the Cloud SQL PSC endpoint port through the tunnel
3. Store the connection string as a Devin Secret referencing `localhost:<port>`
4. Enable the PostgreSQL/MySQL MCP in Settings > MCP Marketplace

## Cost (Estimates)

> Costs below are approximate estimates based on published cloud provider pricing at time of writing. Verify current pricing on the provider's pricing page before budgeting.

| Resource | Approximate Cost |
|---|---|
| PSC endpoint (Google APIs) | **Free** (no per-hour charge) |
| PSC endpoint (Published Services) | ~$0.01/hr per endpoint |
| Data processed | ~$0.01/GB |
| **Total (Google APIs)** | **Free** + data charges |
| **Total (Published Service)** | **~$7.30/month** + data charges |

PSC for Google APIs is free. The primary cost is data processing charges.

## Reference

- [Private Service Connect Overview](https://cloud.google.com/vpc/docs/private-service-connect)
- [Accessing Google APIs through PSC](https://cloud.google.com/vpc/docs/configure-private-service-connect-apis)
- [Published Services](https://cloud.google.com/vpc/docs/configure-private-service-connect-producer)
- [Cloud SQL with PSC](https://cloud.google.com/sql/docs/mysql/configure-private-service-connect)
- [PSC Pricing](https://cloud.google.com/vpc/pricing#private-service-connect-pricing)
