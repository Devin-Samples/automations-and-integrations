# Checkmarx → Devin Integration

> **Status: Planned** — This integration is on the roadmap but not yet implemented. The architecture below describes the intended design.

Trigger Devin to remediate SAST findings when Checkmarx completes a scan and reports vulnerabilities above a configured severity threshold.

## Planned Architecture

```
Developer pushes code
        ↓
Checkmarx scan triggered (via CI or webhook)
        ↓
Scan completes → Checkmarx sends webhook
        ↓
Webhook receiver parses results
        ↓
HIGH/CRITICAL findings found?
    YES → Call Devin API with structured remediation prompt
        ↓
Devin fixes vulnerabilities → pushes to branch
        ↓
Checkmarx re-scans → findings resolved → PR unblocked
```

## Integration Points

### Option A: Checkmarx One Webhooks

Checkmarx One supports webhooks that fire on scan completion. The receiver would:

1. Receive the scan-complete webhook
2. Call the Checkmarx One API to fetch detailed findings
3. Filter by severity (HIGH/CRITICAL)
4. Build a structured prompt with file paths, line numbers, and vulnerability descriptions
5. Call the Devin API to create a remediation session

### Option B: CI Pipeline Integration

Similar to the Trivy integration — run the Checkmarx CLI (`cx`) within GitHub Actions:

```yaml
# Planned workflow structure
jobs:
  checkmarx-scan:
    steps:
      - name: Run Checkmarx scan
        uses: Checkmarx/ast-github-action@latest
        with:
          project_name: ${{ github.repository }}
          cx_tenant: ${{ secrets.CX_TENANT }}
          cx_client_id: ${{ secrets.CX_CLIENT_ID }}
          cx_client_secret: ${{ secrets.CX_CLIENT_SECRET }}
          additional_params: --report-format json --output-path .

      - name: Parse results and trigger Devin
        env:
          DEVIN_API_KEY: ${{ secrets.DEVIN_API_KEY }}
        run: |
          python3 .github/scripts/trigger_devin_checkmarx.py \
            --results-file cx_result.json \
            --repo "${{ github.repository }}" \
            --branch "${{ github.head_ref }}" \
            --pr-number "${{ github.event.pull_request.number }}"
```

## Checkmarx Webhook Payload (Expected Format)

```json
{
  "id": "scan-abc123",
  "status": "Completed",
  "project": {
    "id": "proj-xyz789",
    "name": "my-org/my-repo"
  },
  "branch": "feature/new-endpoint",
  "createdAt": "2024-01-15T10:30:00Z",
  "scanType": "sast",
  "resultsOverview": {
    "highSeverity": 3,
    "mediumSeverity": 12,
    "lowSeverity": 45,
    "infoSeverity": 8
  },
  "detailsUrl": "https://ast.checkmarx.net/projects/proj-xyz789/scans/scan-abc123"
}
```

## Key Design Decisions (Planned)

- **Loop prevention**: Skip Devin-authored PRs (`devin-ai-integration[bot]`)
- **Severity threshold**: Default to HIGH and CRITICAL; configurable via environment variable
- **One-time attempt**: Label PRs after first remediation attempt to prevent retrigger
- **Result enrichment**: Fetch full vulnerability details (data flow, code snippets) from Checkmarx API before passing to Devin
- **Language support**: Checkmarx supports 30+ languages; the integration will be language-agnostic

## Required Secrets (Planned)

| Secret | Description |
|--------|-------------|
| `CX_TENANT` | Checkmarx One tenant name |
| `CX_CLIENT_ID` | OAuth2 client ID for Checkmarx One API |
| `CX_CLIENT_SECRET` | OAuth2 client secret |
| `DEVIN_API_KEY` | Devin API key |

## Contributing

If you'd like to help implement this integration, please open an issue or pull request. Key areas that need work:

1. Checkmarx One API client for fetching detailed SAST results
2. Result parser that extracts file paths, line numbers, and data flow information
3. Prompt builder optimized for Checkmarx finding format
4. End-to-end testing with a sample Checkmarx project

## References

- [Devin API Documentation](https://docs.devin.ai/api-reference/overview)
- [Checkmarx One Documentation](https://checkmarx.com/resource/documents/en/34965-68610-checkmarx-one.html)
- [Checkmarx GitHub Action](https://github.com/Checkmarx/ast-github-action)
- [Checkmarx One REST API](https://checkmarx.com/resource/documents/en/34965-68611-checkmarx-one-api.html)
