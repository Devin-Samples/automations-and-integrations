# GCP Network Connectivity Patterns

Patterns for connecting Devin to private resources in Google Cloud VPCs.

## Patterns

| Pattern | Directory | Description | Status |
|---|---|---|---|
| **IAP Tunneling** | [`iap-tunneling/`](iap-tunneling/) | Identity-Aware Proxy TCP forwarding — no public IPs, IAM-based access, free | Available |
| **Private Service Connect** | [`private-service-connect/`](private-service-connect/) | Private IP for Google APIs, managed services, and your own published services | Available |

## Which Pattern?

- **Single VM or service** → [IAP Tunneling](iap-tunneling/) — free, identity-aware, zero network exposure
- **Google managed service (Cloud SQL, GCS, BigQuery, etc.)** → [Private Service Connect](private-service-connect/) — private IP for Google APIs
- **Your own service published to other VPCs** → [Private Service Connect (Service Attachment)](private-service-connect/) — ILB-backed, consumer-initiated

## Combining Patterns

Private Service Connect provides private IPs for Google APIs but requires Devin to be inside the VPC. Pair it with:
- **IAP Tunneling** to reach a VM that has access to the PSC endpoints

## Reference

- [Identity-Aware Proxy TCP Forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding)
- [Private Service Connect](https://cloud.google.com/vpc/docs/private-service-connect)
