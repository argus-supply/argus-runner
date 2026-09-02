#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$script_dir/.." && pwd -P)"
source_dir=""
version=""
output_dir=""
skip_build=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) source_dir="${2:?missing source}"; shift 2 ;;
    --version) version="${2:?missing version}"; shift 2 ;;
    --output) output_dir="${2:?missing output}"; shift 2 ;;
    --skip-build) skip_build=true; shift ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ -d "$source_dir/.git" && -n "$version" && -n "$output_dir" ]] || { printf 'source, version, and output are required\n' >&2; exit 2; }
for command_name in curl git node pnpm python3 tar zstd sha256sum; do
  command -v "$command_name" >/dev/null || { printf 'missing command: %s\n' "$command_name" >&2; exit 1; }
done
input="$repo_dir/release-inputs/runner-v${version}.json"
[[ -f "$input" ]] || { printf 'release input is missing: %s\n' "$input" >&2; exit 1; }
expected_commit="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["argusCommit"])' "$input")"
actual_commit="$(git -C "$source_dir" rev-parse HEAD)"
[[ "$actual_commit" == "$expected_commit" ]] || { printf 'ARGUS source is %s, expected %s\n' "$actual_commit" "$expected_commit" >&2; exit 1; }
if [[ "$skip_build" != true ]]; then
  (cd "$source_dir/deepseek-harness" && pnpm run build)
fi
runner_package="$source_dir/deepseek-harness/packages/ssh/ssh-runner"
runner_js="$runner_package/lib/bin.js"
[[ -s "$runner_js" ]] || { printf 'standalone Runner build is missing\n' >&2; exit 1; }
if grep -Eq "from ['\"]@deepseek-ai/" "$runner_js"; then
  printf 'standalone Runner still imports workspace packages\n' >&2
  exit 1
fi
work_dir="$(mktemp -d)"
cleanup() { rm -rf -- "$work_dir"; }
trap cleanup EXIT INT TERM
mkdir -p "$output_dir"
for arch in amd64 arm64; do
  node_arch="x64"
  [[ "$arch" == "arm64" ]] && node_arch="arm64"
  stage="$work_dir/stage-$arch"
  mkdir -p "$stage/node_modules/node-pty/prebuilds/linux-$node_arch" "$stage/licenses/argus-runner" "$stage/licenses/node-pty"
  cp "$runner_js" "$stage/runner.js"
  cp "$runner_package/scripts/install-managed.sh" "$stage/install-managed.sh"
  cp "$runner_package/scripts/doctor.sh" "$stage/doctor.sh"
  cp "$runner_package/node_modules/node-pty/package.json" "$stage/node_modules/node-pty/package.json"
  cp -R "$runner_package/node_modules/node-pty/lib" "$stage/node_modules/node-pty/lib"
  cp -R "$runner_package/node_modules/node-pty/prebuilds/linux-$node_arch/." "$stage/node_modules/node-pty/prebuilds/linux-$node_arch/"
  cp "$source_dir/deepseek-harness/LICENSE" "$stage/licenses/argus-runner/LICENSE"
  cp "$runner_package/node_modules/node-pty/LICENSE" "$stage/licenses/node-pty/LICENSE"
  chmod 0555 "$stage/runner.js" "$stage/install-managed.sh" "$stage/doctor.sh"
  node_name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["nodeArchives"][sys.argv[2]]["name"])' "$input" "$arch")"
  node_sha="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["nodeArchives"][sys.argv[2]]["sha256"])' "$input" "$arch")"
  curl -fsSLo "$stage/node-runtime.tar.gz" "https://nodejs.org/dist/v22.19.0/$node_name"
  printf '%s  %s\n' "$node_sha" "$stage/node-runtime.tar.gz" | sha256sum --check --status
  python3 "$script_dir/make_manifest.py" --stage "$stage" --input "$input" --arch "$arch"
  cp "$stage/manifest.json" "$output_dir/manifest_linux_${arch}.json"
  cp "$stage/sbom.cdx.json" "$output_dir/sbom_linux_${arch}.cdx.json"
  cp "$stage/provenance.json" "$output_dir/provenance_linux_${arch}.json"
  epoch="$(git -C "$source_dir" show -s --format=%ct HEAD)"
  python3 "$script_dir/archive.py" --root "$stage" --epoch "$epoch" | zstd -19 -T0 -q -o "$output_dir/argus-runner_${version}_linux_${arch}.tar.zst"
done
cp "$input" "$output_dir/release-input.json"
sha256sum "$output_dir"/* > "$output_dir/SHA256SUMS"
printf 'packaged ARGUS Runner %s\n' "$version"
