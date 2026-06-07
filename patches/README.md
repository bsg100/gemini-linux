# patches/

Kernel patches for the Gemini PDA Linux bring-up project.

Patches are organised by target kernel version and subsystem. They are plain `git diff` output against the tagged kernel release and can be applied with `git apply` or `patch -p1`.

**Before authoring or modifying any patch, read [`STANDARDS.md`](STANDARDS.md).**
It codifies the observability, error-handling, hardware-value-sourcing,
dual-boot, and DTS rules that every patch is reviewed against. Worked examples
of each rule being broken are in [`../code_review/findings.md`](../code_review/findings.md).

## Directory structure

```
patches/
  STANDARDS.md              # Rules every patch must follow — read first
  v6.6/                     # Target: Linux 6.6 LTS
    dts/  drm/  gpio/  panel/  phy/  regulator/  usb/
      NNNN-short-description.patch
```

## Applying all patches

Prefer the build script, which validates with `git apply --check` before
applying and fails loudly on a bad patch:

```bash
cd ~/gemini_linux
./scripts/build.sh patch
```

The manual equivalent (note: `find | sort` orders by *path*, so the `NNNN`
prefixes define order only *within* a subsystem directory, not globally — this
is fine because patches touch disjoint files):

```bash
cd ~/linux-6.6
for p in $(find ~/gemini_linux/patches/v6.6 -name '*.patch' | sort); do
    echo "Applying $p"
    git apply --check "$p" || { echo "FAILED: $p"; exit 1; }
    git apply "$p"
done
```

## Adding a new patch

Make changes directly in `~/linux-6.6`, then:

```bash
cd ~/linux-6.6
git diff HEAD -- path/to/changed/file.c \
    > ~/gemini_linux/patches/v6.6/subsystem/NNNN-short-description.patch
```

Use four-digit sequence numbers (`0001`, `0002`, …) so patches apply in order.
