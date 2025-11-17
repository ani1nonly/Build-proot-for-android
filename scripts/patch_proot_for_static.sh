#!/usr/bin/env bash
set -euo pipefail
# Purpose: add/ensure a 'static' target and enforce PIC + static-friendly flags.
# Usage:
#   scripts/patch_proot_for_static.sh --cc aarch64-linux-musl-gcc --ar aarch64-linux-musl-ar --arch aarch64

CC=""
AR=""
ARCH="aarch64"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cc) CC="$2"; shift 2;;
    --ar) AR="$2"; shift 2;;
    --arch) ARCH="$2"; shift 2;;
    *) echo "Unknown arg $1"; exit 1;;
  esac
done

# Attempt to find proot top-level Makefile or src/Makefile
TOP_MK=""
if [ -f "Makefile" ]; then TOP_MK="Makefile"; fi
if [ -f "src/Makefile" ]; then TOP_MK="src/Makefile"; fi
if [ -z "$TOP_MK" ]; then
  echo "Unable to find a Makefile to patch; aborting."
  exit 1
fi

echo "Patching Makefile: ${TOP_MK}"

# This patch is conservative: it injects STATIC_CC/STATIC_AR variables and adds a 'static' target
# if not present. Will not overwrite existing 'static' target if present.

# Create a backup
cp "${TOP_MK}" "${TOP_MK}.bak"

# Inject CC/AR variables near top of file if not present
if ! grep -q "STATIC_CC" "${TOP_MK}"; then
  awk -v cc="$CC" -v ar="$AR" '
  BEGIN {added=0}
  {
    print
    if (!added && NR==1) {
      print "\n# Added by patch_proot_for_static.sh to support musl static builds"
      print "STATIC_CC ?= " cc
      print "STATIC_AR ?= " ar
      print "STATIC_CFLAGS ?= -fPIC -O2 -static"
      print "STATIC_LDFLAGS ?= -static"
      added=1
    }
  }
  ' "${TOP_MK}" > "${TOP_MK}.new" && mv "${TOP_MK}.new" "${TOP_MK}"
fi

# Add a 'static' target that compiles objects with STATIC_CC and archives them into libproot.a
if ! grep -q "^static:" "${TOP_MK}"; then
  cat >> "${TOP_MK}" <<'EOF'

# static: build object files with STATIC_CC and create a static archive libproot.a
static:
	@echo "Building static objects (musl) ..."
	@$(MAKE) clean || true
	# Build objects using STATIC_CC if present. Most proot Makefiles have src/ objects
if [ -d src ] ; then \
  (cd src && CC="$(STATIC_CC)" CFLAGS="$(STATIC_CFLAGS)" LDFLAGS="$(STATIC_LDFLAGS)" make -j$(shell nproc) all) ; \
else \
  CC="$(STATIC_CC)" CFLAGS="$(STATIC_CFLAGS)" LDFLAGS="$(STATIC_LDFLAGS)" make -j$(shell nproc) ; \
fi
	@echo "Creating libproot.a ..."
	@find . -name '*.o' | xargs -r $(STATIC_AR) rcs libproot.a || true
	@echo "Static archive libproot.a created."
EOF
fi

echo "Makefile patched. Backup saved at ${TOP_MK}.bak"
