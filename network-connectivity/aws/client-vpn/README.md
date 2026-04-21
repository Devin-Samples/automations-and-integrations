# AWS Client VPN

> Planned — not yet implemented.

Full subnet-level VPN access to private AWS resources via an AWS Client VPN endpoint. Use this when Devin needs to reach multiple services across a private subnet.

## When to Use

- Devin needs access to **multiple private services** (e.g., Artifactory + database + internal APIs)
- You need full network-layer routing, not just single-port tunnels
- Your organization already uses AWS Client VPN for developer access

## Planned Components

- CloudFormation template for Client VPN endpoint with certificate-based auth
- IAM and security group configuration
- Client configuration generation
- Devin environment integration (OpenVPN config as a secret)

## Reference

- [AWS Client VPN Administrator Guide](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/what-is.html)
- [Mutual Authentication](https://docs.aws.amazon.com/vpn/latest/clientvpn-admin/client-authentication.html#mutual)
