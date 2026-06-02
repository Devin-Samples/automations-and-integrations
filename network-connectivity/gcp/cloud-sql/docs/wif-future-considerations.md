# WIF Future Considerations

> How Workload Identity Federation could enable credential-less authentication if the Devin platform adds per-session identity.

## Current State

GCP [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) (WIF) is the gold standard for cross-cloud authentication — it eliminates stored credentials entirely by exchanging an external identity for short-lived GCP tokens.

**WIF is not viable for Devin today** because Devin sessions have no external identity to federate:

| WIF Identity Source | Devin Status | Why |
|---|---|---|
| AWS IAM Role | Not available | Devin VMs are Firecracker microVMs with no AWS IAM role or instance metadata |
| OIDC Token | Not available | Devin platform does not issue per-session OIDC tokens |
| SAML Assertion | Not available | No SAML IdP issues assertions for Devin sessions |

## What Would Make WIF Viable

### Option 1: Per-Session OIDC Identity (Recommended)

If the Devin platform operated an OIDC-compliant identity provider and issued a signed JWT to each session, WIF would work:

```
Devin Session                        GCP
────────────                         ───
1. Session starts with a signed
   JWT from Cognition OIDC IdP
   (claims: org_id, session_id, etc.)

2. gcloud / client library sends ───► GCP Security Token Service
   JWT to STS                          validates against WIF Pool config
                                       (trusts Cognition OIDC issuer)

3. Receives GCP access token    ◄─── issues short-lived GCP token
                                       bound to the target GSA

4. Cloud SQL Auth Proxy uses
   GCP token to connect         ────► Cloud SQL (mTLS)
```

**Customer setup would be:**

```bash
# Create WIF Pool
gcloud iam workload-identity-pools create devin-pool \
  --location="global" \
  --display-name="Devin Sessions" \
  --project=PROJECT_ID

# Add OIDC provider
gcloud iam workload-identity-pools providers create-oidc devin-oidc \
  --location="global" \
  --workload-identity-pool="devin-pool" \
  --issuer-uri="https://auth.devin.ai" \
  --allowed-audiences="PROJECT_ID" \
  --attribute-mapping="google.subject=assertion.org_id" \
  --project=PROJECT_ID

# Bind GSA
gcloud iam service-accounts add-iam-policy-binding \
  devin-db@PROJECT_ID.iam.gserviceaccount.com \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/devin-pool/attribute.org_id/DEVIN_ORG_ID"
```

**Devin blueprint would be:**

```yaml
initialize: |
  curl -o /usr/local/bin/cloud-sql-proxy \
    https://storage.googleapis.com/cloud-sql-connectors/cloud-sql-proxy/v2.14.2/cloud-sql-proxy.linux.amd64
  chmod +x /usr/local/bin/cloud-sql-proxy

maintenance: |
  # OIDC token automatically available as $DEVIN_OIDC_TOKEN or via a file
  export GOOGLE_APPLICATION_CREDENTIALS=/etc/devin/wif-config.json
  cloud-sql-proxy $CLOUD_SQL_INSTANCE --port 5432 &
  sleep 3
```

### Option 2: AWS IAM Identity for Devin VMs

If Devin VMs gained an AWS IAM role (even a shared one per org), the standard WIF-via-AWS flow would work without any Devin platform changes. However, this is architecturally harder given the Firecracker isolation model.

## Benefits of WIF (When Available)

| Benefit | Detail |
|---|---|
| **No stored GCP credentials** | No SA key to generate, store, rotate, or leak |
| **Short-lived tokens** | GCP access tokens expire in ~1 hour; auto-refreshed |
| **Fine-grained attribution** | GCP audit logs show the Devin org ID / session ID, not just a key ID |
| **Simpler onboarding** | Customer creates a WIF Pool once; adding new apps is a GSA binding, not a new key |
| **Better for compliance** | No credential lifecycle management; tokens are ephemeral |

## Cross-Cloud Applicability

The same OIDC identity would also enable:
- **Azure Federated Credentials** — authenticate to Azure AD as a federated workload identity
- **Any OIDC Relying Party** — HashiCorp Vault, AWS (via `AssumeRoleWithWebIdentity`), etc.
- **Customer-operated OIDC-aware proxies** — verify Devin session identity at the network edge

## Recommendation

If the Devin platform team evaluates adding per-session identity, OIDC is the most portable standard. A single OIDC issuer would unlock credential-less authentication across GCP, Azure, AWS, and any OIDC-compatible system.

Until then, use [Option A (Customer-Hosted Proxy)](option-a-customer-hosted-proxy.md) for production or [Option B (SA Key)](option-b-sa-key-on-devin.md) for POC.
