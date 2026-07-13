#!/bin/bash
# build.sh — Gemini PDA Linux 6.6 kernel build script
#
# Run this inside the build VM (ssh -p 5522 root@localhost).
# See claude.md "Build Environment" for VM details.
#
# Usage:
#   ./build.sh [clean]      # build kernel; optionally clean first
#   ./build.sh patch        # apply all project patches to kernel tree
#   ./build.sh config       # generate .config only
#   ./build.sh module <path> # build a single driver object for testing
#
# Environment variables:
#   LINUX_SRC   Path to kernel source tree (default: ~/linux-6.6)
#   PATCHES_DIR Path to project patches directory (default: ~/gemini_linux/patches/v6.6)
#   JOBS        Parallel build jobs (default: nproc)
#   BUILD_NN    Build number — sets KBUILD_BUILD_VERSION so the kernel
#               banner (#NNN in `uname -a`) matches the build-pack build
#               number exactly (added 2026-07-13; before this the banner
#               was the VM's incrementing .version counter, which drifted
#               from the build number)

set -euo pipefail

LINUX_SRC="${LINUX_SRC:-$HOME/linux-6.6}"
PATCHES_DIR="${PATCHES_DIR:-$HOME/gemini_linux/patches/v6.6}"
CONFIG_FRAGMENTS="${CONFIG_FRAGMENTS:-$HOME/gemini_linux/configs}"
JOBS="${JOBS:-$(nproc)}"
ARCH=arm64

die() { echo "ERROR: $*" >&2; exit 1; }

[[ -d "$LINUX_SRC" ]] || die "Kernel source not found at $LINUX_SRC"

case "${1:-build}" in

patch)
    echo "==> Applying patches from $PATCHES_DIR"
    cd "$LINUX_SRC"
    for patch in $(find "$PATCHES_DIR" -name '*.patch' | sort); do
        echo "  $patch"
        git apply --check "$patch" || die "Patch check failed: $patch"
        git apply "$patch"
    done
    echo "==> All patches applied"
    ;;

config)
    echo "==> Generating .config"
    cd "$LINUX_SRC"
    # TODO: replace defconfig with gemini_defconfig once created
    make ARCH=$ARCH defconfig
    if [[ -d "$CONFIG_FRAGMENTS" ]]; then
        frags=$(find "$CONFIG_FRAGMENTS" -name '*.config' | sort)
        if [[ -n "$frags" ]]; then
            echo "==> Merging config fragments: $frags"
            ./scripts/kconfig/merge_config.sh -m .config $frags
            make ARCH=$ARCH olddefconfig
        fi
    fi
    echo "==> .config written"
    ;;

module)
    target="${2:-}"
    [[ -n "$target" ]] || die "Usage: $0 module <drivers/path/to/file.o>"
    echo "==> Building $target"
    cd "$LINUX_SRC"
    make ARCH=$ARCH -j"$JOBS" "$target"
    echo "==> Done: $LINUX_SRC/$target"
    ;;

clean)
    echo "==> Cleaning kernel tree"
    cd "$LINUX_SRC"
    make mrproper
    echo "==> Clean done"
    ;;

build)
    echo "==> Building kernel (JOBS=$JOBS)"
    cd "$LINUX_SRC"
    [[ -f .config ]] || { echo "  No .config — running defconfig first"; make ARCH=$ARCH defconfig; }
    make ARCH=$ARCH -j"$JOBS" ${BUILD_NN:+KBUILD_BUILD_VERSION="$BUILD_NN"} Image.gz dtbs modules
    echo "==> Build complete"
    echo "    Image:   $LINUX_SRC/arch/arm64/boot/Image.gz"
    echo "    Modules: run 'make ARCH=$ARCH modules_install INSTALL_MOD_PATH=<dir>'"
    ;;

*)
    die "Unknown command: ${1}. Use: patch | config | module | clean | build"
    ;;
esac
