# AWS SSM Port Forwarding

Secure tunnel access to private VPC resources using AWS Systems Manager Session Manager — no VPN, no jump box, no inbound security group rules, no public IPs.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Your Machine / Devin                       │
│                                                               │
│  AWS CLI + Session Manager Plugin                            │
│  IAM User: <env>-ssm-portforward-user                        │
│  (scoped to port-forwarding on ONE specific instance)         │
│                                                               │
│  localhost:<port> ──► SSM Port-Forwarding Session             │
└──────────────┬───────────────────────────────────────────────┘
               │ (encrypted SSM channel over HTTPS)
               ▼
┌──────────────────────────────────────────────────────────────┐
│  AWS VPC — NO Internet Gateway, NO NAT                        │
│                                                               │
│  ┌─────────────────────┐    ┌────────────────────────────┐   │
│  │  VPC Endpoints       │    │  Private Subnet             │   │
│  │  ├─ ssm              │    │  ┌────────────────────────┐ │   │
│  │  ├─ ssmmessages      │◄──►│  │  EC2 Relay Instance    │ │   │
│  │  ├─ ec2messages      │    │  │  (Amazon Linux 2023)    │ │   │
│  │  └─ s3 (gateway)     │    │  │                         │ │   │
│  └─────────────────────┘    │  │  Your private service   │ │   │
│                              │  │  or mock server :<port> │ │   │
│                              │  └────────────────────────┘ │   │
│                              └────────────────────────────┘   │
│                                                               │
│  Security Groups:                                            │
│  ├─ Relay SG: target port from VPC CIDR only                 │
│  └─ VPC Endpoint SG: HTTPS (443) from VPC CIDR              │
└──────────────────────────────────────────────────────────────┘
```

## How It Works

1. The EC2 relay instance runs inside a private VPC with **no Internet Gateway** — zero inbound traffic from the internet is possible
2. Three SSM Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`) allow the SSM agent on the instance to register and communicate with the SSM service without internet access
3. An S3 Gateway Endpoint allows the instance to install packages via `dnf` (Amazon Linux repos are hosted on S3)
4. A dedicated IAM user has **fine-grained permissions** scoped to:
   - Port-forwarding sessions only (no interactive shell)
   - This specific instance only (no other targets)
   - Managing only their own sessions
5. The SSM Session Manager Plugin on your local machine establishes an encrypted tunnel, mapping `localhost:<port>` to the relay instance's `<port>`

## Resources Created

| Resource | Type | Purpose |
|---|---|---|
| VPC | `AWS::EC2::VPC` | Isolated network with no internet access |
| Private Subnets (x2) | `AWS::EC2::Subnet` | Two AZs for resilience |
| Route Table | `AWS::EC2::RouteTable` | Local routes only |
| S3 Gateway Endpoint | `AWS::EC2::VPCEndpoint` | Package manager access |
| SSM Interface Endpoints (x3) | `AWS::EC2::VPCEndpoint` | SSM agent communication |
| VPC Endpoint Security Group | `AWS::EC2::SecurityGroup` | HTTPS from VPC CIDR |
| Relay Security Group | `AWS::EC2::SecurityGroup` | Target port from VPC CIDR |
| EC2 Instance Role + Profile | `AWS::IAM::Role` | SSM managed instance |
| EC2 Relay Instance | `AWS::EC2::Instance` | Relay box (+ optional mock server) |
| IAM Port-Forward User | `AWS::IAM::User` | Fine-grained SSM-only access |
| IAM Policy | `AWS::IAM::Policy` | Scoped to instance + document |
| IAM Access Key | `AWS::IAM::AccessKey` | Credentials for the user |

## Quick Start

### Prerequisites

- AWS CLI v2
- [Session Manager Plugin](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
- An AWS account with permissions to create CloudFormation stacks with IAM resources

### 1. Deploy the Stack

```bash
# Deploy with mock server enabled (default) to test the pattern
aws cloudformation create-stack \
  --stack-name ssm-private-access \
  --template-body file://template.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1

# Wait for completion (~5 minutes for VPC endpoints)
aws cloudformation wait stack-create-complete \
  --stack-name ssm-private-access \
  --region us-east-1
```

### 2. Retrieve Credentials

```bash
# Get all stack outputs
aws cloudformation describe-stacks \
  --stack-name ssm-private-access \
  --query 'Stacks[0].Outputs' \
  --output table \
  --region us-east-1

# Export the fine-grained user credentials
export AWS_ACCESS_KEY_ID=<SsmPortForwardAccessKeyId>
export AWS_SECRET_ACCESS_KEY=<SsmPortForwardSecretAccessKey>
export AWS_DEFAULT_REGION=us-east-1
```

### 3. Establish the Tunnel

```bash
aws ssm start-session \
  --target <RelayInstanceId> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8081"],"localPortNumber":["8081"]}'
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

# Connection status
curl -s http://localhost:8081/api/status | jq
# → {"connected":true,"source":"ssm-port-forwarding","network":"private-vpc","ingress":"none"}
```

### 5. Teardown

```bash
aws cloudformation delete-stack \
  --stack-name ssm-private-access \
  --region us-east-1
```

## Parameters

| Parameter | Default | Description |
|---|---|---|
| `EnvironmentName` | `ssm-private-access` | Prefix for all resource names |
| `VpcCidr` | `10.200.0.0/16` | VPC CIDR block |
| `PrivateSubnetACidr` | `10.200.1.0/24` | First private subnet CIDR |
| `PrivateSubnetBCidr` | `10.200.2.0/24` | Second private subnet CIDR |
| `InstanceType` | `t3.micro` | EC2 instance type |
| `TargetPort` | `8081` | Port the private service listens on |
| `EnableMockServer` | `true` | Install nginx mock server for testing |

## IAM Policy Details

The `<env>-ssm-portforward-user` has the minimum permissions needed for port-forwarding:

```json
{
  "Statement": [
    {
      "Sid": "AllowStartSessionOnInstance",
      "Effect": "Allow",
      "Action": ["ssm:StartSession"],
      "Resource": ["arn:aws:ec2:REGION:ACCOUNT:instance/INSTANCE_ID"],
      "Condition": {
        "BoolIfExists": {
          "ssm:SessionDocumentAccessCheck": "true"
        }
      }
    },
    {
      "Sid": "AllowPortForwardDocumentOnly",
      "Effect": "Allow",
      "Action": ["ssm:StartSession"],
      "Resource": ["arn:aws:ssm:REGION::document/AWS-StartPortForwardingSession"]
    },
    {
      "Sid": "AllowTerminateOwnSession",
      "Effect": "Allow",
      "Action": ["ssm:TerminateSession", "ssm:ResumeSession"],
      "Resource": ["arn:aws:ssm:REGION:ACCOUNT:session/${aws:username}-*"]
    },
    {
      "Sid": "AllowDescribeInstances",
      "Effect": "Allow",
      "Action": [
        "ssm:DescribeInstanceInformation",
        "ssm:GetConnectionStatus",
        "ssm:DescribeSessions",
        "ec2:DescribeInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

This user **cannot**:
- Start interactive shell sessions (only port-forwarding)
- Target any other EC2 instance
- Use any other SSM document
- Terminate other users' sessions

## Devin Environment Integration

Add to your Devin environment configuration to establish connectivity at session start:

**`initialize`** (one-time — installs the SSM plugin):

```bash
curl -s "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/ubuntu_64bit/session-manager-plugin.deb" \
  -o /tmp/session-manager-plugin.deb && sudo dpkg -i /tmp/session-manager-plugin.deb && rm /tmp/session-manager-plugin.deb
```

**Secrets** (stored in Devin settings):

| Secret Name | Value | Scope |
|---|---|---|
| `SSM_RELAY_ACCESS_KEY_ID` | `<SsmPortForwardAccessKeyId>` from stack outputs | org or repo |
| `SSM_RELAY_SECRET_ACCESS_KEY` | `<SsmPortForwardSecretAccessKey>` from stack outputs | org or repo |

**`maintenance`** (every session — establishes the tunnel):

```bash
# Establish SSM tunnel to private service in background
AWS_ACCESS_KEY_ID="$SSM_RELAY_ACCESS_KEY_ID" \
AWS_SECRET_ACCESS_KEY="$SSM_RELAY_SECRET_ACCESS_KEY" \
AWS_DEFAULT_REGION=us-east-1 \
aws ssm start-session \
  --target <INSTANCE_ID> \
  --document-name AWS-StartPortForwardingSession \
  --parameters '{"portNumber":["8081"],"localPortNumber":["8081"]}' &
```

## Cost

| Resource | Approximate Cost |
|---|---|
| 3 SSM Interface Endpoints | ~$0.02/hr per AZ (~$0.04/hr total for 2 AZs) |
| EC2 `t3.micro` | ~$0.01/hr |
| S3 Gateway Endpoint | Free |
| **Total** | **~$0.05/hr** (~$36/month if left running) |

Tear down the stack when not in use to avoid charges.

## Reference

- [AWS SSM Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [SSM Port Forwarding](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html#sessions-start-port-forwarding)
- [VPC Endpoints for SSM](https://docs.aws.amazon.com/systems-manager/latest/userguide/setup-create-vpc.html)
- [Session Manager Plugin Installation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)
