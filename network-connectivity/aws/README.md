# AWS Network Connectivity Patterns

Patterns for connecting Devin to private resources in AWS VPCs.

## Patterns

| Pattern | Directory | Description | Status |
|---|---|---|---|
| **SSM Port Forwarding** | [`ssm-port-forwarding/`](ssm-port-forwarding/) | Encrypted tunnel via SSM Session Manager — no VPN, no public IPs, no inbound rules | Available |
| **Client VPN** | [`client-vpn/`](client-vpn/) | Full subnet-level routing via AWS Client VPN endpoint with mutual TLS | Available |
| **PrivateLink** | [`privatelink/`](privatelink/) | Service-to-service connectivity via VPC endpoints — traffic stays on AWS backbone | Available |
| **RDS Connectivity** | [`rds/`](rds/) | RDS PostgreSQL — customer-hosted proxy, IAM credentials, or direct connect | Available |

## Which Pattern?

- **Single port/service** → [SSM Port Forwarding](ssm-port-forwarding/) — simplest, cheapest, zero network exposure
- **Multiple services across a subnet** → [Client VPN](client-vpn/) — full routing, OpenVPN-compatible
- **Managed AWS service (RDS, Secrets Manager, ECR, etc.)** → [PrivateLink](privatelink/) — private IP for AWS services
- **Your own service exposed to another VPC** → [PrivateLink (Endpoint Service)](privatelink/) — NLB-backed, no peering needed
- **RDS PostgreSQL database** → [RDS Connectivity](rds/) — three architecture options (proxy, IAM credentials, direct connect) with detailed setup and example blueprints

## Reference

- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Client VPN](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
