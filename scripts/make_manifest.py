#!/usr/bin/env python3
"""Create one Runner target manifest, SBOM, and provenance record."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib

parser = argparse.ArgumentParser()
parser.add_argument("--stage", required=True, type=pathlib.Path)
parser.add_argument("--input", required=True, type=pathlib.Path)
parser.add_argument("--arch", required=True)
args = parser.parse_args()
record = json.loads(args.input.read_text())


def digest(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


files = [{"path": str(path.relative_to(args.stage)), "size": path.stat().st_size, "sha256": digest(path), "executable": bool(path.stat().st_mode & 0o111)} for path in sorted(args.stage.rglob("*")) if path.is_file()]
manifest = {"schemaVersion": 1, "component": "runner", "version": record["version"], "os": "linux", "arch": args.arch, "argusCommit": record["argusCommit"], "runnerProtocol": record["runnerProtocol"], "managedProfile": record["managedProfile"], "nodeVersion": record["nodeVersion"], "files": files}
(args.stage / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
sbom = {"bomFormat": "CycloneDX", "specVersion": "1.5", "version": 1, "metadata": {"component": {"type": "application", "name": "argus-runner", "version": record["version"]}}, "components": [{"type": "framework", "name": "node", "version": record["nodeVersion"]}, {"type": "library", "name": "node-pty", "version": "1.2.0-beta.15"}]}
(args.stage / "sbom.cdx.json").write_text(json.dumps(sbom, indent=2, sort_keys=True) + "\n")
provenance = {"schemaVersion": 1, "builder": "argus-supply/argus-runner", "buildType": "argus-source-handoff", "subject": {"name": "argus-runner", "version": record["version"], "target": f"linux/{args.arch}"}, "materials": [{"uri": record["argusSource"], "digest": {"gitCommit": record["argusCommit"]}}, {"uri": f"https://nodejs.org/dist/v{record['nodeVersion']}/{record['nodeArchives'][args.arch]['name']}", "digest": {"sha256": record["nodeArchives"][args.arch]["sha256"]}}]}
(args.stage / "provenance.json").write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
