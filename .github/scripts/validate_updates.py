#!/usr/bin/env python3
"""Validate MyFinc's public notifications and patches manifest."""
import json
import re
import sys
from datetime import datetime
from pathlib import Path
from urllib.parse import urlparse

MANIFEST = Path("docs/updates/manifest.json")
ALLOWED_LEVELS = {"info", "success", "warning", "error"}
RELEASE_PREFIX = "/K3NYEL/myfinc/releases/"


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def nonempty_string(value, field: str) -> None:
    if not isinstance(value, str) or not value.strip():
        fail(f"{field} must be a non-empty string")


def valid_date(value, field: str, optional: bool = False) -> None:
    if optional and value is None:
        return
    nonempty_string(value, field)
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        fail(f"{field} must be an ISO-8601 date/time")


def main() -> None:
    if not MANIFEST.is_file():
        fail(f"missing {MANIFEST}")
    try:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"manifest is not valid UTF-8 JSON: {exc}")

    if not isinstance(data, dict):
        fail("root must be a JSON object")
    if data.get("schemaVersion") != 1:
        fail("schemaVersion must equal 1")
    valid_date(data.get("updatedAt"), "updatedAt")
    notifications = data.get("notifications")
    patches = data.get("patches")
    if not isinstance(notifications, list) or len(notifications) > 50:
        fail("notifications must be a list with at most 50 entries")
    if not isinstance(patches, list) or len(patches) > 30:
        fail("patches must be a list with at most 30 entries")

    seen_ids = set()
    for index, item in enumerate(notifications):
        prefix = f"notifications[{index}]"
        if not isinstance(item, dict):
            fail(f"{prefix} must be an object")
        for field in ("id", "title", "message"):
            nonempty_string(item.get(field), f"{prefix}.{field}")
        ident = item["id"].strip()
        if ident in seen_ids:
            fail(f"duplicate id: {ident}")
        seen_ids.add(ident)
        valid_date(item.get("publishedAt"), f"{prefix}.publishedAt", optional=True)
        if item.get("level", "info") not in ALLOWED_LEVELS:
            fail(f"{prefix}.level must be one of {sorted(ALLOWED_LEVELS)}")

    for index, item in enumerate(patches):
        prefix = f"patches[{index}]"
        if not isinstance(item, dict):
            fail(f"{prefix} must be an object")
        for field in ("id", "version", "title", "summary"):
            nonempty_string(item.get(field), f"{prefix}.{field}")
        ident = item["id"].strip()
        if ident in seen_ids:
            fail(f"duplicate id: {ident}")
        seen_ids.add(ident)
        valid_date(item.get("publishedAt"), f"{prefix}.publishedAt", optional=True)
        notes = item.get("notes", [])
        if not isinstance(notes, list) or len(notes) > 30 or any(not isinstance(note, str) for note in notes):
            fail(f"{prefix}.notes must be a list of at most 30 strings")
        if not isinstance(item.get("required", False), bool):
            fail(f"{prefix}.required must be boolean")
        release_url = item.get("releaseUrl")
        if release_url is not None:
            nonempty_string(release_url, f"{prefix}.releaseUrl")
            parsed = urlparse(release_url)
            if parsed.scheme != "https" or parsed.netloc != "github.com" or not parsed.path.startswith(RELEASE_PREFIX):
                fail(f"{prefix}.releaseUrl must point to a MyFinc GitHub Release")

    print(f"Manifest valid: {len(notifications)} notification(s), {len(patches)} patch(es).")


if __name__ == "__main__":
    main()
