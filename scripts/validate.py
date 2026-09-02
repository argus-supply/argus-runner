#!/usr/bin/env python3
"""Validate Runner release input records without accessing ARGUS source."""

from __future__ import annotations

import json
import pathlib
import re

root = pathlib.Path(__file__).resolve().parents[1]
records = sorted((root / "release-inputs").glob("runner-v*.json"))
if not records:
    raise SystemExit("no Runner release input records")
for path in records:
    value = json.loads(path.read_text())
    if value.get("schemaVersion") != 1 or not re.fullmatch(r"[0-9a-f]{40}", value.get("argusCommit", "")):
        raise SystemExit(f"invalid Runner release record: {path.name}")
    if path.name != f"runner-v{value.get('version')}.json":
        raise SystemExit(f"Runner release filename/version mismatch: {path.name}")
    if set(value.get("nodeArchives", {})) != {"amd64", "arm64"}:
        raise SystemExit(f"Runner release target mismatch: {path.name}")
    for archive in value["nodeArchives"].values():
        if not re.fullmatch(r"[0-9a-f]{64}", archive.get("sha256", "")):
            raise SystemExit(f"invalid Node archive digest: {path.name}")
print(f"validated {len(records)} Runner release record(s)")
