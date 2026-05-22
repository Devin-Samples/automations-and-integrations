# AWS PrivateLink

Private connectivity to AWS services or your own services via VPC endpoints — traffic stays on the AWS backbone, no public internet exposure. Use this for service-to-service connectivity without VPC peering.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Devin Session (VM)                          │
│                                                               │
│  Application / CLI / MCP Server                              │
│  Connects to: vpce-xxxx.svc.us-east-1.vpce.amazonaws.com    │
│  or private DNS: rds-instance.xxxx.us-east-1.rds.amazonaws.com │
│                                                               │
└──────────────┬───────────────────────────────────────────────┘
               │ (via SSM tunnel or VPN into VPC)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  AWS VPC                                                       │
│                                                               │
│  ┌────────────────────────────┐                               │
│  │  Private Subnet             │                               │
│  │  ┌────────────────────────┐ │                               │
│  │  │  Interface VPC Endpoint │ │   ┌──────────────────────┐  │
│  │  │  ENI: 10.0.1.x         │─┼──►│  AWS Service          │  │
│  │  │                         │ │   │  (RDS, S3, Secrets    │  │
│  │  └────────────────────────┘ │   │   Manager, etc.)       │  │
│  └────────────────────────────┘   └──────────────────────────┘  │
│                                                               │
│  OR: Endpoint Service (your own NLB-backed service)           │
│  ┌────────────────────────────┐                               │
│  │  VPC Endpoint Service       │                               │
│  │  (backed by NLB)           │──► Your private microservice  │
│  └────────────────────────────┘                               │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

### Interface VPC Endpoints (AWS Services)

1. An **Interface VPC Endpoint** creates an ENI (Elastic Network Interface) with a private IP inside your VPC
2. Traffic to the AWS service is routed through the ENI instead of the internet
3. **Private DNS** (optional) resolves the service's public FQDN to the private endpoint IP
4. Security groups control which resources in the VPC can reach the endpoint

### VPC Endpoint Services (Your Own Services)

1. You expose your service behind a **Network Load Balancer** (NLB)
2. A **VPC Endpoint Service** wraps the NLB, making it available to VPC endpoints in other VPCs
3. Consumers create Interface VPC Endpoints pointing to your Endpoint Service
4. Traffic flows: Consumer VPC → VPC Endpoint → NLB → Your service

## When to Use

- Devin needs to access a **managed AWS service** (RDS, Secrets Manager, ECR, S3, etc.) privately
- You want to expose an internal service to Devin without VPC peering or internet transit
- You need to keep all traffic on the AWS backbone for compliance
- You're on Devin's **Dedicated Deployment** and want to use [PrivateLink integration](https://docs.devin.ai/enterprise/deployment/dedicated_saas_private_networking)

## Supported AWS Services

Common services available via Interface VPC Endpoints:

| Service | Endpoint Service Name | Use Case |
|---|---|---|
| RDS | `com.amazonaws.<region>.rds` | Private database access |
| Secrets Manager | `com.amazonaws.<region>.secretsmanager` | Credential retrieval |
| ECR (API + Docker) | `com.amazonaws.<region>.ecr.api` / `.dkr` | Private container registry |
| S3 (Interface) | `com.amazonaws.<region>.s3` | S3 access via private IP |
| SSM | `com.amazonaws.<region>.ssm` | Systems Manager (used by SSM port-forwarding pattern) |
| STS | `com.amazonaws.<region>.sts` | Token service for IAM roles |
| CloudWatch Logs | `com.amazonaws.<region>.logs` | Log delivery |

See the [full list](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-privatelink-support.html) for all supported services.

## Prerequisites

- AWS CLI v2
- An AWS account with permissions to create VPC endpoints, security groups, and (optionally) NLBs
- A VPC with private subnets

## Quick Start: Interface VPC Endpoint (AWS Service)

This example creates a PrivateLink endpoint for AWS Secrets Manager.

### 1. Create the VPC Endpoint

```bash
# Variables
REGION="us-east-1"
VPC_ID="vpc-xxxxxxxx"
SUBNET_IDS="subnet-aaaa,subnet-bbbb"  # Private subnets

# Create security group for the endpoint
VPCE_SG=$(aws ec2 create-security-group \
  --group-name devin-vpce-secretsmanager \
  --description "Allow HTTPS to Secrets Manager VPC Endpoint" \
  --vpc-id $VPC_ID \
  --region $REGION \
  --query GroupId --output text)

# Allow HTTPS from VPC CIDR
aws ec2 authorize-security-group-ingress \
  --group-id $VPCE_SG \
  --protocol tcp \
  --port 443 \
  --cidr 10.0.0.0/16 \
  --region $REGION

# Create the interface endpoint
VPCE_ID=$(aws ec2 create-vpc-endpoint \
  --vpc-id $VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name com.amazonaws.${REGION}.secretsmanager \
  --subnet-ids $SUBNET_IDS \
  --security-group-ids $VPCE_SG \
  --private-dns-enabled \
  --region $REGION \
  --query VpcEndpoint.VpcEndpointId --output text)

echo "VPC Endpoint: $VPCE_ID"
```

### 2. Verify

From an instance inside the VPC:

```bash
# DNS should resolve to private IP
nslookup secretsmanager.us-east-1.amazonaws.com
# → 10.0.x.x (private endpoint IP)

# Retrieve a secret (uses the private path)
aws secretsmanager get-secret-value \
  --secret-id my-secret \
  --region us-east-1
```

### 3. Teardown

```bash
aws ec2 delete-vpc-endpoints --vpc-endpoint-ids $VPCE_ID --region $REGION
aws ec2 delete-security-group --group-id $VPCE_SG --region $REGION
```

## Quick Start: VPC Endpoint Service (Your Own Service)

### 1. Create an NLB for Your Service

```bash
# Create NLB
NLB_ARN=$(aws elbv2 create-load-balancer \
  --name devin-internal-svc \
  --type network \
  --scheme internal \
  --subnets subnet-aaaa subnet-bbbb \
  --region $REGION \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Create target group pointing to your service
TG_ARN=$(aws elbv2 create-target-group \
  --name devin-svc-targets \
  --protocol TCP \
  --port 8081 \
  --vpc-id $VPC_ID \
  --target-type ip \
  --region $REGION \
  --query 'TargetGroups[0].TargetGroupArn' --output text)

# Register your service's IP
aws elbv2 register-targets \
  --target-group-arn $TG_ARN \
  --targets Id=10.0.1.100 \
  --region $REGION

# Create listener
aws elbv2 create-listener \
  --load-balancer-arn $NLB_ARN \
  --protocol TCP \
  --port 8081 \
  --default-actions Type=forward,TargetGroupArn=$TG_ARN \
  --region $REGION
```

### 2. Create the Endpoint Service

```bash
# Create endpoint service
SVC_ID=$(aws ec2 create-vpc-endpoint-service-configuration \
  --network-load-balancer-arns $NLB_ARN \
  --acceptance-required \
  --region $REGION \
  --query ServiceConfiguration.ServiceId --output text)

SVC_NAME=$(aws ec2 describe-vpc-endpoint-service-configurations \
  --service-ids $SVC_ID \
  --region $REGION \
  --query 'ServiceConfigurations[0].ServiceName' --output text)

echo "Endpoint Service: $SVC_NAME"
```

### 3. Connect from Another VPC

```bash
# In the consumer VPC (e.g., Devin's Dedicated Deployment VPC)
aws ec2 create-vpc-endpoint \
  --vpc-id $CONSUMER_VPC_ID \
  --vpc-endpoint-type Interface \
  --service-name $SVC_NAME \
  --subnet-ids $CONSUMER_SUBNET_IDS \
  --region $REGION
```

## Devin Environment Integration

PrivateLink endpoints require Devin to be **inside the VPC** to use the private DNS resolution. Pair this with [SSM Port Forwarding](../ssm-port-forwarding/) or [Client VPN](../client-vpn/).

For Devin **Dedicated Deployment** customers, PrivateLink can connect Devin's managed VPC directly to your services — see [Dedicated Deployment Private Networking](https://docs.devin.ai/enterprise/deployment/dedicated_saas_private_networking).

## Cost

| Resource | Approximate Cost |
|---|---|
| Interface VPC Endpoint | ~$0.01/hr per AZ (~$7.30/month per AZ) |
| Data processed | ~$0.01/GB |
| NLB (Endpoint Service) | ~$0.023/hr + LCU charges |
| **Total (2 AZ endpoint)** | **~$15/month** + data charges |

## Reference

- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
- [Interface VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/create-interface-endpoint.html)
- [VPC Endpoint Services](https://docs.aws.amazon.com/vpc/latest/privatelink/endpoint-service-overview.html)
- [Supported AWS Services](https://docs.aws.amazon.com/vpc/latest/privatelink/aws-services-privatelink-support.html)
- [PrivateLink Pricing](https://aws.amazon.com/privatelink/pricing/)
