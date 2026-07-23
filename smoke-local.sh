#!/bin/bash
# Local smoke test: run smoke-payload.sh in an arm64 noble container.
# Usage: smoke-local.sh [package.click]  (defaults to newest in out/)
set -e
SRC="$(dirname "$(readlink -f "$0")")"
CLICK="${1:-$(ls -t "$SRC"/out/*.click | head -1)}"
podman run --rm -i --arch arm64 --security-opt label=disable \
	-v "$SRC":/src -v "$(readlink -f "$CLICK")":/tmp/pkg.click:ro \
	ubuntu:noble /src/smoke-payload.sh /tmp/pkg.click
