# Audit-Log Repo Onboarding Watcher

A lightweight Python poller that watches the [Devin v3 enterprise audit-log API](https://docs.devin.ai/api-reference/v3/audit-logs/enterprise-audit-logs) for `create_git_permission` events and automatically creates Devin sessions to set up each newly-added repository's environment blueprint.

## Architecture

```
Devin Enterprise API                    Watcher                          Devin Org API
┌───────────────────┐                  ┌───────────────────────┐        ┌─────────────────┐
│ GET /v3/enterprise│   poll every N s │                       │  POST  │ /v3/org/{id}/   │
│   /audit-logs     │ <────────────────│  watcher.py           │ ─────> │   sessions      │
│                   │                  │                       │        │                 │
│ action=           │  new events      │ 1. Filter new repos   │        │ Creates Devin   │
│  create_git_      │ ────────────────>│ 2. Deduplicate        │        │ session with    │
│  permission       │                  │ 3. Build setup prompt │        │ setup prompt    │
│                   │                  │ 4. Create session(s)  │        │                 │
└───────────────────┘                  └───────────────────────┘        └─────────────────┘
                                              │
                                              │ persist
                                              ▼
                                       .watcher_state.json
```

## How It Works

1. The watcher polls `GET /v3/enterprise/audit-logs?action=create_git_permission` on a configurable interval (default: 60 s).
2. For each event, it extracts repository URLs from the `data.git_permissions` array.
3. URLs are deduplicated against a local state file so repos are only onboarded once.
4. For each new repo, it calls `POST /v3/organizations/{org_id}/sessions` with a prompt that instructs Devin to:
   - Clone and set up the repository
   - Install dependencies and verify the build/tests
   - Capture the working setup in a `.yaml` environment configuration
5. The timestamp checkpoint and seen-URL set are persisted to `.watcher_state.json`.

### Processing Modes

| Mode | Behavior |
|---|---|
| `immediate` (default) | Creates one Devin session per new repo as soon as the event is observed. |
| `batch` | Collects repos over a configurable window (`BATCH_WINDOW_SECONDS`, default 300 s) and fires a single session for the entire batch. Useful when many repos are granted simultaneously. |

## Prerequisites

- Python 3.10+
- A Devin **service-user API key** (`cog_...`) with:
  - `ManageEnterpriseSettings` — to read enterprise audit logs
  - `ManageOrgSessions` — to create sessions in the target org
  - (Optional) `ImpersonateOrgSessions` — if using `CREATE_AS_USER_ID`
- The target Devin organization ID (`org-...`)

## Quick Start

```bash
# 1. Clone and enter the directory
cd repo-onboarding/audit-log-watcher

# 2. Create a virtualenv and install dependencies
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

# 3. Configure
cp .env.example .env
# Edit .env — set DEVIN_API_KEY and DEVIN_ORG_ID at minimum

# 4. Run
python watcher.py              # long-running poller
python watcher.py --once       # single poll cycle then exit (cron-friendly)
```

### Docker

```bash
docker build -t audit-log-watcher .
docker run --env-file .env audit-log-watcher
```

### Cron

For a cron-based approach instead of a long-running process:

```cron
*/5 * * * * cd /path/to/audit-log-watcher && /path/to/.venv/bin/python watcher.py --once >> /var/log/watcher.log 2>&1
```

## Configuration

| Environment Variable | Required | Default | Description |
|---|---|---|---|
| `DEVIN_API_KEY` | Yes | — | Devin service-user API key (`cog_...`) |
| `DEVIN_ORG_ID` | Yes | — | Target Devin organization ID (`org-...`) |
| `POLL_INTERVAL_SECONDS` | No | `60` | Seconds between poll cycles |
| `LOOKBACK_SECONDS` | No | `86400` | How far back to look on first run (default 24 h) |
| `STATE_FILE` | No | `.watcher_state.json` | Path to the checkpoint file |
| `CREATE_AS_USER_ID` | No | — | User ID to impersonate when creating sessions |
| `MAX_ACU_LIMIT` | No | — | Maximum ACU budget per setup session |
| `PROCESSING_MODE` | No | `immediate` | `immediate` or `batch` |
| `BATCH_WINDOW_SECONDS` | No | `300` | Collection window for batch mode |
| `IGNORE_PATTERNS` | No | — | Comma-separated substrings; matching repo URLs are skipped |
| `LOG_LEVEL` | No | `INFO` | Python log level |

## File Structure

```
audit-log-watcher/
├── watcher.py          # Main poller and session creator
├── requirements.txt    # Python dependencies
├── .env.example        # Environment variable template
├── Dockerfile          # Container image definition
└── README.md
```

## State File Format

The watcher persists a JSON checkpoint so it survives restarts:

```json
{
  "last_processed_timestamp": 1700000000,
  "seen_repo_urls": [
    "https://github.com/org/repo-a",
    "https://github.com/org/repo-b"
  ],
  "pending_batch": []
}
```

To re-process all repos, delete the state file and restart.

## Security Considerations

- **Never commit `.env` or the state file.** The `.env` file contains your API key.
- The service-user key should be scoped to the minimum permissions listed above.
- When running in production, use a secrets manager (AWS SSM, Azure Key Vault, etc.) instead of a `.env` file.
- The `CREATE_AS_USER_ID` feature requires `ImpersonateOrgSessions` — grant this only to trusted service users.

## Audit-Log Event Reference

The watcher listens for the `create_git_permission` action. The event `data` payload contains:

```json
{
  "git_permissions": [
    {
      "permission_id": "perm-...",
      "repo_url": "https://github.com/org/repo",
      "read_only": false
    }
  ]
}
```

Related audit-log actions (not used by this watcher, but available for extension):

| Action | Description |
|---|---|
| `create_git_permission` | Repo access granted to a Devin org |
| `update_git_permission` | Repo permission modified (e.g., read-only toggled) |
| `delete_git_permission` | Repo access removed |

## Extending

Some ideas for building on this pattern:

- **Playbook-driven setup**: Pass a `playbook_id` in the session payload to use a standardized onboarding playbook instead of a free-form prompt.
- **Slack notifications**: Post to a Slack channel when new repos are onboarded (see [`messaging/slack/`](../../messaging/slack/)).
- **Webhook variant**: Instead of polling, deploy as a webhook receiver if your enterprise can forward audit events via a webhook integration.
- **Multi-org routing**: Inspect the `org_id` on each audit event and route the setup session to the correct organization.

## API Reference

- [List Audit Logs (Enterprise)](https://docs.devin.ai/api-reference/v3/audit-logs/enterprise-audit-logs)
- [List Audit Logs (Organization)](https://docs.devin.ai/api-reference/v3/audit-logs/organizations-audit-logs)
- [Create Session](https://docs.devin.ai/api-reference/v3/sessions/post-organizations-sessions)
- [Authentication & Service Users](https://docs.devin.ai/api-reference/authentication)
