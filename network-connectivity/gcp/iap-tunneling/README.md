# GCP IAP Tunneling

> Planned — not yet implemented.

Secure tunnel access to GCP VMs using Identity-Aware Proxy (IAP) TCP forwarding — no public IPs, IAM-based access control, free.

## When to Use

- Devin needs to reach a **service running on a GCP VM** inside a VPC
- You want identity-based access control (Google IAM) with no VPN
- You need a GCP-native equivalent of AWS SSM port forwarding
- Cost is a concern (IAP TCP forwarding is free)

## Planned Components

- Terraform module for VPC, firewall rules, and IAP configuration
- Service account with scoped IAM bindings
- Devin environment integration (`gcloud compute start-iap-tunnel`)

## Reference

- [IAP TCP Forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [IAP Firewall Rules](https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule)
