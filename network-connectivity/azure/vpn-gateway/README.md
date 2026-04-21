# Azure VPN Gateway

> Planned — not yet implemented.

Point-to-site or site-to-site VPN connectivity for full subnet-level routing into Azure VNets.

## When to Use

- Devin needs access to **multiple services across an Azure VNet**
- You need full network-layer routing, not just single-port tunnels
- Your organization already uses Azure VPN Gateway for developer access

## Planned Components

- ARM / Bicep template for VPN Gateway with P2S configuration
- Certificate generation and client configuration
- Devin environment integration (OpenVPN config as a secret)

## Reference

- [Azure VPN Gateway](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-about-vpngateways)
- [Point-to-Site Configuration](https://learn.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-howto-point-to-site-resource-manager-portal)
