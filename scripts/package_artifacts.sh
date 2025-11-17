#!/usr/bin/env bash
set -euo pipefail
ARCH=${1:-aarch64}
WORKDIR="$(pwd)"
OUT_DIR="${WORKDIR}/build/${ARCH}"
mkdir -p "${OUT_DIR}"
# Placeholder - move artifacts if needed
echo "Ensure build/${ARCH}/libproot.so exists."
ls -lh "${OUT_DIR}" || true
