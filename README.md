# ARGUS Runner releases

The main ARGUS repository is the only Runner source authority. This repository stores immutable build-input records, controlled packaging scripts, and Linux amd64/arm64 releases; it does not contain an independently editable Runner source copy.

`scripts/package-from-source.sh` must run against the exact ARGUS commit recorded under `release-inputs/`. It builds the standalone Runner in that checkout, bundles the pinned Node runtime and matching node-pty prebuild, and emits manifests, digests, SBOM, and provenance. The resulting assets are uploaded to the matching immutable tag.

ARGUS nodes never fetch these assets. The ARGUS control plane downloads, verifies, and transfers them through staged SFTP bootstrap or upgrade.
