#!/usr/bin/env python3
"""
Audit-Log Repo Onboarding Watcher

Polls the Devin v3 enterprise audit-log endpoint for ``create_git_permission``
events and automatically creates a Devin session to set up each newly-added
repository's environment blueprint.

Supports two processing modes:

* **immediate** — one setup session per repo, created as soon as the event
  is observed.
* **batch** — repos are collected over a configurable window and a single
  session is created for the whole batch.

State is persisted to a local JSON file so the watcher survives restarts
without re-processing old events.

Usage::

    # Copy .env.example -> .env, fill in values, then:
    pip install -r requirements.txt
    python watcher.py            # long-running poller
    python watcher.py --once     # single poll cycle then exit

Environment variables are documented in ``.env.example``.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Any

import requests

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

DEVIN_API_BASE = "https://api.devin.ai/v3"

logger = logging.getLogger("audit-log-watcher")


def _env(name: str, default: str | None = None, required: bool = False) -> str | None:
    val = os.environ.get(name, default)
    if required and not val:
        raise SystemExit(f"error: required environment variable {name} is not set")
    return val


class Config:
    """Validated runtime configuration loaded from environment variables."""

    def __init__(self) -> None:
        self.api_key: str = _env("DEVIN_API_KEY", required=True)  # type: ignore[assignment]
        self.org_id: str = _env("DEVIN_ORG_ID", required=True)  # type: ignore[assignment]
        self.poll_interval = int(_env("POLL_INTERVAL_SECONDS", "60"))  # type: ignore[arg-type]
        self.lookback = int(_env("LOOKBACK_SECONDS", "86400"))  # type: ignore[arg-type]
        self.state_file = Path(_env("STATE_FILE", ".watcher_state.json"))  # type: ignore[arg-type]
        self.create_as_user_id = _env("CREATE_AS_USER_ID")
        self.max_acu_limit = _env("MAX_ACU_LIMIT")
        self.processing_mode = _env("PROCESSING_MODE", "immediate")
        self.batch_window = int(_env("BATCH_WINDOW_SECONDS", "300"))  # type: ignore[arg-type]
        self.ignore_patterns = [
            p.strip()
            for p in (_env("IGNORE_PATTERNS", "") or "").split(",")
            if p.strip()
        ]
        self.log_level = _env("LOG_LEVEL", "INFO")


# ---------------------------------------------------------------------------
# State persistence
# ---------------------------------------------------------------------------

def load_state(path: Path) -> dict[str, Any]:
    if path.exists():
        with open(path) as f:
            return json.load(f)
    return {}


def save_state(path: Path, state: dict[str, Any]) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w") as f:
        json.dump(state, f, indent=2)
    tmp.replace(path)


# ---------------------------------------------------------------------------
# Devin API helpers
# ---------------------------------------------------------------------------

def _headers(api_key: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }


def fetch_audit_logs(
    cfg: Config,
    time_after: int,
    cursor: str | None = None,
) -> dict[str, Any]:
    """Fetch a page of audit logs filtered to ``create_git_permission``."""
    url = f"{DEVIN_API_BASE}/enterprise/audit-logs"
    params: dict[str, Any] = {
        "action": "create_git_permission",
        "order": "asc",
        "time_after": time_after,
        "first": 200,
    }
    if cursor:
        params["after"] = cursor

    resp = requests.get(url, headers=_headers(cfg.api_key), params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def create_setup_session(
    cfg: Config,
    repo_url: str,
    repo_name: str | None = None,
) -> dict[str, Any]:
    """Create a Devin session to onboard a single repository."""
    display = repo_name or repo_url
    prompt = (
        f"Set up the {display} repository from scratch: install dependencies, "
        f"get the build and tests working. Then capture the working setup "
        f"steps in the .yaml environment configuration.\n\n"
        f"Repository URL: {repo_url}\n"
        f"Should we get the app running: yes"
    )
    return _create_session(cfg, prompt, title=f"Auto-onboard: {display}")


def create_batch_session(
    cfg: Config,
    repos: list[dict[str, str]],
) -> dict[str, Any]:
    """Create a single Devin session to onboard multiple repositories."""
    repo_lines = "\n".join(
        f"- {r.get('name', r['url'])} ({r['url']})" for r in repos
    )
    prompt = (
        f"Set up the following repositories from scratch. For each one, "
        f"install dependencies, get the build and tests working, and capture "
        f"the working setup steps in a .yaml environment configuration.\n\n"
        f"Repositories:\n{repo_lines}\n\n"
        f"Should we get the apps running: yes"
    )
    return _create_session(
        cfg,
        prompt,
        title=f"Auto-onboard: {len(repos)} repo(s)",
    )


def _create_session(
    cfg: Config,
    prompt: str,
    title: str,
) -> dict[str, Any]:
    url = f"{DEVIN_API_BASE}/organizations/{cfg.org_id}/sessions"
    payload: dict[str, Any] = {
        "prompt": prompt,
        "title": title,
        "tags": ["auto-onboard", "audit-log-watcher"],
    }
    if cfg.create_as_user_id:
        payload["create_as_user_id"] = cfg.create_as_user_id
    if cfg.max_acu_limit:
        payload["max_acu_limit"] = int(cfg.max_acu_limit)

    logger.info("Creating session: %s", title)
    resp = requests.post(
        url, headers=_headers(cfg.api_key), json=payload, timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


# ---------------------------------------------------------------------------
# Event processing
# ---------------------------------------------------------------------------

def extract_repos_from_event(event: dict[str, Any]) -> list[dict[str, str]]:
    """Pull repo URL and optional name from an audit-log event's data."""
    data = event.get("data", {})
    repos: list[dict[str, str]] = []

    permissions = data.get("git_permissions", [])
    if isinstance(permissions, list):
        for perm in permissions:
            url = perm.get("repo_url") or perm.get("repository_url", "")
            if url:
                repos.append({"url": url, "name": _repo_name_from_url(url)})

    if not repos:
        url = data.get("repo_url") or data.get("repository_url", "")
        if url:
            repos.append({"url": url, "name": _repo_name_from_url(url)})

    return repos


def _repo_name_from_url(url: str) -> str:
    """Derive ``owner/repo`` from a git URL."""
    url = url.rstrip("/")
    if url.endswith(".git"):
        url = url[:-4]
    parts = url.rsplit("/", 2)
    if len(parts) >= 2:
        return f"{parts[-2]}/{parts[-1]}"
    return url


def should_ignore(repo_url: str, patterns: list[str]) -> bool:
    return any(p in repo_url for p in patterns)


# ---------------------------------------------------------------------------
# Main poll loop
# ---------------------------------------------------------------------------

def _process_repos_immediate(
    cfg: Config,
    repos: list[dict[str, str]],
    seen_urls: set[str],
    state: dict[str, Any],
) -> None:
    """Create one session per repo; queue failures for retry."""
    failed: list[dict[str, str]] = []
    for repo in repos:
        try:
            result = create_setup_session(cfg, repo["url"], repo["name"])
            session_url = result.get("url", result.get("session_id", "unknown"))
            logger.info("Session created for %s: %s", repo["name"], session_url)
            seen_urls.add(repo["url"])
        except requests.RequestException as exc:
            logger.error("Failed to create session for %s: %s", repo["url"], exc)
            failed.append(repo)

    pending_retry = state.get("pending_retry", [])
    retry_urls = {r["url"] for r in pending_retry}
    for repo in failed:
        if repo["url"] not in retry_urls:
            pending_retry.append(repo)
    state["pending_retry"] = pending_retry


def poll_once(cfg: Config, state: dict[str, Any]) -> dict[str, Any]:
    """Run one poll cycle. Returns the updated state dict."""
    last_ts = state.get("last_processed_timestamp")
    if last_ts is None:
        last_ts = int(time.time()) - cfg.lookback

    # Retry repos that failed session creation on previous cycles.
    pending_retry = state.get("pending_retry", [])
    if pending_retry and cfg.processing_mode == "immediate":
        logger.info("Retrying %d repo(s) from previous failures", len(pending_retry))
        seen_urls_for_retry: set[str] = set(state.get("seen_repo_urls", []))
        state["pending_retry"] = []
        _process_repos_immediate(cfg, pending_retry, seen_urls_for_retry, state)
        state["seen_repo_urls"] = sorted(seen_urls_for_retry)

    logger.info("Polling audit logs since %s", last_ts)

    new_repos: list[dict[str, str]] = []
    seen_urls: set[str] = set(state.get("seen_repo_urls", []))
    this_cycle: set[str] = set()
    latest_ts = last_ts
    cursor: str | None = None

    while True:
        page = fetch_audit_logs(cfg, time_after=last_ts, cursor=cursor)
        items = page.get("items", [])
        if not items:
            break

        for event in items:
            event_ts = event.get("created_at", 0)
            if event_ts > latest_ts:
                latest_ts = event_ts

            repos = extract_repos_from_event(event)
            for repo in repos:
                url = repo["url"]
                if url in seen_urls or url in this_cycle:
                    logger.debug("Skipping already-seen repo: %s", url)
                    continue
                if should_ignore(url, cfg.ignore_patterns):
                    logger.info("Ignoring repo (matched ignore pattern): %s", url)
                    seen_urls.add(url)
                    continue
                this_cycle.add(url)
                new_repos.append(repo)
                logger.info("New repo permission detected: %s", url)

        if not page.get("has_next_page"):
            break
        cursor = page.get("end_cursor")

    if not new_repos:
        logger.info("No new repos found")
    elif cfg.processing_mode == "batch":
        logger.info("Batch mode: queuing %d repo(s) for batch window", len(new_repos))
        pending = state.get("pending_batch", [])
        pending.extend(new_repos)
        state["pending_batch"] = pending
        seen_urls.update(this_cycle)
    else:
        _process_repos_immediate(cfg, new_repos, seen_urls, state)

    state["last_processed_timestamp"] = latest_ts
    state["seen_repo_urls"] = sorted(seen_urls)
    return state


def flush_batch(cfg: Config, state: dict[str, Any]) -> dict[str, Any]:
    """Send a single session for all repos collected during the batch window."""
    pending = state.get("pending_batch", [])
    if not pending:
        return state

    logger.info("Flushing batch of %d repo(s)", len(pending))
    try:
        result = create_batch_session(cfg, pending)
        session_url = result.get("url", result.get("session_id", "unknown"))
        logger.info("Batch session created: %s", session_url)
    except requests.RequestException as exc:
        logger.error("Failed to create batch session: %s", exc)
        return state

    state["pending_batch"] = []
    return state


def run(cfg: Config, *, once: bool = False) -> None:
    state = load_state(cfg.state_file)
    batch_timer = time.monotonic()

    while True:
        try:
            state = poll_once(cfg, state)
            save_state(cfg.state_file, state)

            if cfg.processing_mode == "batch":
                elapsed = time.monotonic() - batch_timer
                if elapsed >= cfg.batch_window:
                    state = flush_batch(cfg, state)
                    save_state(cfg.state_file, state)
                    batch_timer = time.monotonic()

            if once:
                if cfg.processing_mode == "batch":
                    state = flush_batch(cfg, state)
                    save_state(cfg.state_file, state)
                break
        except requests.RequestException as exc:
            logger.error("API error during poll cycle: %s", exc)

        logger.debug("Sleeping %ds", cfg.poll_interval)
        time.sleep(cfg.poll_interval)


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Poll Devin audit logs and auto-onboard new repositories.",
    )
    parser.add_argument(
        "--once",
        action="store_true",
        help="Run a single poll cycle then exit (useful for cron).",
    )
    args = parser.parse_args()

    # Load .env file if present (lightweight, no extra dependency)
    env_path = Path(".env")
    if env_path.exists():
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                key, _, value = line.partition("=")
                os.environ.setdefault(key.strip(), value.strip())

    cfg = Config()

    logging.basicConfig(
        level=getattr(logging, cfg.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)-8s %(name)s  %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )

    logger.info(
        "Starting audit-log watcher  org=%s  mode=%s  interval=%ds",
        cfg.org_id,
        cfg.processing_mode,
        cfg.poll_interval,
    )

    try:
        run(cfg, once=args.once)
    except KeyboardInterrupt:
        logger.info("Shutting down")
        sys.exit(0)


if __name__ == "__main__":
    main()
