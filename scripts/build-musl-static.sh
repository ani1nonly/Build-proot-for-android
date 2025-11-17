#!/usr/bin/env bash
set -euo pipefail
# Usage:
#  scripts/build-musl-static.sh --arch aarch64 --proot-repo 'https://github.com/CypherpunkArmory/proot.git' --proot-ref master

ARCH="aarch64"
PROOT_REPO="https://github.com/CypherpunkArmory/proot.git"
PROOT_REF="master"
WORKDIR="$(pwd)"
BUILD_DIR="${WORKDIR}/work_build"
OUT_DIR="${WORKDIR}/build"

function usage() {
  cat <<EOF
Usage: $0 --arch <aarch64|arm> --proot-repo <git-url> --proot-ref <branch|tag|commit>
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch) ARCH="$2"; shift 2;;
    --proot-repo) PROOT_REPO="$2"; shift 2;;
    --proot-ref) PROOT_REF="$2"; shift 2;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

mkdir -p "$BUILD_DIR"
mkdir -p "$OUT_DIR"

echo "Building libproot for arch=${ARCH}"
echo "Using proot repo: ${PROOT_REPO}@${PROOT_REF}"
cd "$BUILD_DIR"

# Choose musl cross triple
case "$ARCH" in
  aarch64|arm64) TRIPLE="aarch64-linux-musl"; CC="${TRIPLE}-gcc"; AR="${TRIPLE}-ar"; STRIP="${TRIPLE}-strip";;
  arm|armv7l) TRIPLE="arm-linux-musleabihf"; CC="${TRIPLE}-gcc"; AR="${TRIPLE}-ar"; STRIP="${TRIPLE}-strip";;
  x86_64) TRIPLE="x86_64-linux-musl"; CC="${TRIPLE}-gcc"; AR="${TRIPLE}-ar"; STRIP="${TRIPLE}-strip";;
  *) echo "Unsupported arch: $ARCH"; exit 1;;
esac

# Ensure toolchain exists in the container
if ! command -v "$CC" >/dev/null 2>&1; then
  echo "Error: expected cross-compiler ${CC} present in the container. Ensure you select the correct Docker image (musl-cross)."
  exit 1
fi

# Clone proot
PROOT_DIR="${BUILD_DIR}/proot-src"
if [ -d "${PROOT_DIR}" ]; then rm -rf "${PROOT_DIR}"; fi
git clone --depth 1 --branch "${PROOT_REF}" "${PROOT_REPO}" "${PROOT_DIR}"

cd "${PROOT_DIR}"

# Apply minimal patch to ensure static build target + PIC objects.
# This script is idempotent.
bash "${WORKDIR}/scripts/patch_proot_for_static.sh" --cc "$CC" --ar "$AR" --arch "$ARCH"

# Build - produce static archive libproot.a (and object files)
# We use MAKEFLAGS to pass CC and ensure PIC and static-friendly flags.
export CC
MAKEFLAGS="V=1"
# Ensure we build objects, then archive
if make -j$(nproc) static; then
  echo "make static succeeded"
else
  echo "make static failed, trying fallback make all"
  make -j$(nproc)
fi

# After build, we expect a libproot.a under src/ or build/ (depending on proot)
# Search for static archives or object files
LIB_A="$(find . -type f -name 'libproot.a' -o -name 'proot.a' | head -n1 || true)"
if [ -z "$LIB_A" ]; then
  # try assembling from object files
  echo "libproot.a not found. Trying to create one from object files."
  OBJS="$(find . -name '*.o' | tr '\n' ' ')"
  if [ -z "$OBJS" ]; then
    echo "No object files found; build likely failed."
    exit 1
  fi
  LIB_A="${BUILD_DIR}/libproot.a"
  $AR rcs "$LIB_A" $OBJS
fi

echo "Static archive produced at: $LIB_A"

# Create a small PIC-friendly shared object wrapper that embeds the static archive
OUT_ARCH_DIR="${OUT_DIR}/${ARCH}"
mkdir -p "${OUT_ARCH_DIR}"
LIB_SO="${OUT_ARCH_DIR}/libproot.so"

echo "Linking final libproot.so (wrapper) into ${LIB_SO} ..."

# The linking command uses musl's linker to include the static archive. We use
# -Wl,--whole-archive to force inclusion of all symbols from the archive.
# Note: linking static objects into a shared object is architecture/toolchain dependent.
# If this fails, you still have libproot.a in $LIB_A which can be linked into a wrapper in your project.
$CC -shared -fPIC -o "${LIB_SO}" -Wl,--whole-archive "${LIB_A}" -Wl,--no-whole-archive -Wl,-soname,libproot.so || {
  echo "Primary linking attempt failed. Trying alternate linker flags..."
  # Alternate attempt: run through ld directly with explicit params (less portable)
  LD=$(dirname $(command -v $CC))/ld || true
  $CC -nostdlib -shared -fPIC -o "${LIB_SO}" -Wl,--whole-archive "${LIB_A}" -Wl,--no-whole-archive || {
    echo "All attempts to create libproot.so failed. You still have a static archive at ${LIB_A}."
    exit 0
  }
}

# Strip to reduce size (optional)
if command -v "$STRIP" >/dev/null 2>&1; then
  $STRIP --strip-unneeded "${LIB_SO}" || true
fi

echo "libproot.so created at: ${LIB_SO}"
echo "Done."
