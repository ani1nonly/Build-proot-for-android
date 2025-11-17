Run locally (you need docker):

docker run --rm -v $(pwd):/work -w /work messense/musl-cross:aarch64 bash -lc "scripts/build-musl-static.sh --arch aarch64 --proot-repo 'https://github.com/CypherpunkArmory/proot.git' --proot-ref master"

Result: build/aarch64/libproot.so (or build/aarch64/libproot.a if linking into .so failed).
