# AWS Network Connectivity Patterns

Patterns for connecting Devin to private resources in AWS VPCs.

## Patterns

| Pattern | Directory | Description | Status |
|---|---|---|---|
| **SSM Port Forwarding** | [`ssm-port-forwarding/`](ssm-port-forwarding/) | Encrypted tunnel via SSM Session Manager — no VPN, no public IPs, no inbound rules | Available |
| **Client VPN** | `client-vpn/` | Full subnet-level routing via AWS Client VPN endpoint | Planned |
| **PrivateLink** | `privatelink/` | Service-to-service connectivity without VPC peering | Planned |

## Which Pattern?

- **Single port/service** → [SSM Port Forwarding](ssm-port-forwarding/) — simplest, cheapest, zero network exposure
- **Multiple services across a subnet** → Client VPN — full routing, OpenVPN-compatible
- **Managed AWS service (RDS, ElastiCache, etc.)** → PrivateLink — private IP for AWS services

## Reference

- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [AWS Client VPN](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html)
- [AWS PrivateLink](https://docs.aws.amazon.com/vpc/latest/privatelink/what-is-privatelink.html)
