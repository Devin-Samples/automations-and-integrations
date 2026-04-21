# GCP Network Connectivity Patterns

Patterns for connecting Devin to private resources in Google Cloud VPCs.

## Patterns

| Pattern | Directory | Description | Status |
|---|---|---|---|
| **IAP Tunneling** | `iap-tunneling/` | Identity-Aware Proxy TCP forwarding — no public IPs, IAM-based access | Planned |
| **Private Service Connect** | `private-service-connect/` | Private IP for Google APIs and your own services | Planned |

## Which Pattern?

- **Single VM or service** → IAP Tunneling — free, identity-aware, zero network exposure
- **Google managed service (Cloud SQL, GCS, etc.)** → Private Service Connect — private IP for Google APIs

## Reference

- [Identity-Aware Proxy TCP Forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect)
