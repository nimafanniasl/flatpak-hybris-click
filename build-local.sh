#!/bin/bash
# Local build: run build-payload.sh in an arm64 noble container (qemu binfmt).
set -e
SRC="$(dirname "$(readlink -f "$0")")"
mkdir -p "$SRC/out"
podman run --rm -i --arch arm64 --security-opt label=disable \
	-v "$SRC":/src -v "$SRC/out":/out \
	-e OUT=/out ubuntu:noble /src/build-payload.sh
