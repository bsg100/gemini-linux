# Reviving a Dead PDA: I Ported Linux 6.6 to the Gemini PDA with Claude as My Pair Programmer

## TL;DR

- Porting a 2018 pocket PDA (MediaTek Helio X27) off its abandoned Android
  3.18 BSP onto mainline-based Linux 6.6, using mostly upstream drivers.
- 259 build-flash-boot iterations in: serial console, storage, display,
  keyboard, charging, and dual-port USB (charge + host-mode ethernet) all
  work on real hardware.
- Open item: internal WiFi/Bluetooth, blocked behind a proprietary
  firmware handshake.
- Claude did the heavy lifting on investigation and patch-writing —
  register-level hardware profiling, golden-harvest comparisons, a test
  for every DTS entry, and build/log bookkeeping at scale.
- I ran every flash and serial capture myself, on physical hardware — that
  boundary never moved. Direction — what to tackle next, when to stop
  chasing a dead end — stayed mine throughout.

## Why this device

In 2018, Planet Computers shipped the Gemini PDA — a pocketable clamshell
with a real keyboard, built around a MediaTek Helio X27. It ran a
customized Android on a Linux 3.18 kernel that vendor support abandoned
years ago. The hardware is fine; the software is a fossil. I own one, and
it's been sitting in a drawer for exactly that reason.

The question I set out to answer:

- Can this device run a *current*, *maintainable* Linux kernel (6.6 LTS)
  using mostly upstream drivers, instead of the vendor's frozen BSP?
- And — since I was doing this in 2026 — what does that kind of embedded
  bring-up look like with an AI agent doing much of the investigation and
  patch-writing?

## Why bother

- Devices like this die twice: once when the vendor stops updates, again
  when the people who understood the board move on and take the knowledge
  with them.
- The Gemini has an active community, but fixing forward on a 3.18 BSP is
  effort spent maintaining a dead end — nothing upstreams, nothing is
  reusable elsewhere.
- Porting to a current LTS kernel changes the shape of the problem:
  - eMMC/MSDC, much of display/IOMMU — already upstream, just *use* it.
  - What's left — the genuinely board-specific, cost-down parts — is a
    much smaller, better-documented surface.
- The bet: less code to maintain, more shared with the kernel community, a
  device that keeps getting security fixes instead of staying frozen at
  2018.

## My approach

- Inventory every piece of hardware, check what already has upstream
  support, write new driver code only for the irreducible remainder.
- Bring the system up in stages, each gated on the previous one actually
  working on hardware, not just compiling:
  serial console → storage → display → input → power → networking.
- No stage gets "probably works":
  - every claim needs a serial capture
  - every patch is applied to a clean kernel tree and tested on the real
    device over FTDI/SSH — never simulated
  - "fixed" means a clean boot log filed next to the sha256 of exactly
    what was flashed, so a regression six weeks later can be told apart
    from a recurrence by pointing at the evidence, not by memory

## The challenges

**Expected:**
- A panel with vendor-only timing values baked into a proprietary
  bootloader.
- A keyboard controller shipped with its pinctrl silently disabled.
- A USB PHY needing vendor-specific session-valid bits forced by hand.

**The expensive, unglamorous kind:**
- **A display IRQ that froze the whole CPU, not just the screen.** The
  MIPI DSI driver requested its interrupt at probe time and unmasked it
  immediately — but the bootloader had left the DSI engine's IRQ line
  asserted low. The kernel acked the interrupt, entered the handler, and
  stalled reading a status register on a still-unclocked block — with the
  line never cleared, the GIC stopped delivering *any* interrupt to that
  core, so the whole CPU wedged, not just display. It looked exactly like
  a hardware bus lock. Diagnosing it took a purpose-built GIC observer
  that could catch an interrupt controller mid-hang and a chain of six
  narrowing experiments (irqs-off survives, irqs-on dies even with
  cpuidle/nohlt disabled, the observer catches SPI 229 stuck ACTIVE,
  `disable_irq()` placed after `request_irq()` is already too late) before
  the real fix fell out: request the IRQ with `IRQ_NOAUTOEN` and only
  `enable_irq()` once the DSI engine is actually clocked and powered.
  Two probe-order bugs, same shape: fixing display *also* surfaced a
  second one — resuming the SMI larb (the memory-interface block behind
  the overlay engine) unconditionally at its own probe hard-hung the MM
  power domain the same way. The safe fix wasn't "pin it active," it was
  making the overlay driver take a runtime-PM device link to the larb it
  actually depends on, so the larb powers up only when something real
  needs it.
- **A big CPU core that never joined SMP — and firmware, not Linux, was
  holding it.** With no core limit, the eight little cores (A53) boot
  cleanly in milliseconds, but the PSCI `CPU_ON` call for the first big
  core (A72) never returns — the boot CPU just blocks inside the SMC
  instruction until ATF's own watchdog fires 14 seconds later and reboots
  the board. It looked identical to the display power-domain bug at
  first glance — "some domain isn't powering on" — until reading the
  actual MT6797 power-domain table in the mainline driver showed it
  defines no CPU-cluster domain at all, which ruled out a whole class of
  Linux-side fixes in one read. The workaround (`maxcpus=8`, skip the A72
  cluster entirely) is the current baseline; the actual bug lives inside
  a firmware blob outside this project's reach.
- **A charging IC mis-identified for years.** Every piece of documentation
  — schematic, vendor DTS, forum threads — named the charger as a Richtek
  RT9466 at I2C address 0x53. Following that lead burned real time (an
  RT9466 driver port, IRQ wiring to a GPIO the schematic specified) before
  a plain I2C bus scan turned up nothing at 0x53 at all — and a chip-ID
  read at 0x6b came back matching a completely different part, TI's
  BQ25896. Every register value anyone had ever cited, sourced from the
  RT9466 datasheet, had quietly been describing the wrong silicon.
  Re-pointing at the correct part meant no custom driver was even needed
  — mainline already has `bq25890_charger.c` — but only after the false
  identity was caught and discarded.
- **Internal WiFi — the one that stayed unglamorous to the end.** MediaTek
  splits this into two independently gated steps: wake the CONSYS
  co-processor's power domain (G2a), then complete a firmware handshake
  with it over a byte-oriented UART-like link called BTIF (G2b). G2a
  passed cleanly — but only after finding that the "known-good" register
  value everyone had been building against was itself wrong: the vendor
  source defined the CONSYS power-control register at one offset, but the
  real offset was 76 bytes further on — the documented one simply
  rejected every write. G2b never passed. Three separate transport
  designs were tried against the firmware handshake — plain
  programmed-I/O, then DMA, then DMA with one clock made optional — and
  all three stalled at the identical timeout, which pointed at a
  precondition set somewhere in the vendor bootloader rather than a
  protocol bug in this driver. The DMA attempts also introduced an
  unrelated eMMC-mount regression that was never root-caused, which
  raised the cost of continuing to experiment against a live device.
  Getting a *provably* pre-firmware register snapshot to compare against
  — the cleanest way to find what precondition was missing — turned out
  to be blocked by the same read-only, write-protected Android userspace
  described above, so the best available evidence stayed post-firmware
  captures with no clean "before" state. After three failed transport
  attempts with no new register-level hypothesis left to try, and a
  roughly 75-100K-line vendor WiFi driver still waiting on the other side
  of the handshake even if it were solved, this was the one call I made
  to stop: park it, and route wireless connectivity through a USB WiFi
  dongle on the already-working host-mode port instead. Bluetooth shares
  the same CONSYS co-processor and is blocked alongside it.

**Current frontier — internal WiFi:**
- MediaTek's CONSYS subsystem: a separate on-package microcontroller
  running proprietary firmware, gating most behavior behind a handshake
  undocumented outside MediaTek.
- Telling "my driver is wrong" from "this only works after vendor firmware
  loads" has meant chasing Android userspace init ordering and a
  write-protected loop device, just to answer: what does this look like
  *before* firmware is even involved?

## Golden reference: harvesting known-good state from the stock firmware

A datasheet tells you what a register *can* do, not what value the vendor
actually put there to make it work. Fastest way to close that gap: run the
stock firmware and read the registers back while it's known-good.

- The device dual-boots two flashable slots (`boot`/`system` = stock
  Android, `boot2`/`linux` = whatever I'm developing) — the factory image
  is never more than a partition flash away.
- Workflow: flash the vendor stack back, boot it, get a shell (serial,
  ADB, or SSH), run a harvest script that dumps every register of
  interest — clock, power-domain, pinctrl state — to a timestamped file.
- That file becomes the reference my driver's own dump gets diffed
  against, register by register, until they match or the divergence
  points at the bug.

**Payoffs:**
- Caught the charger IC misidentification — golden harvest of the I2C bus
  showed a chip ID matching TI's BQ25896, not the RT9466 on the schematic.
- Recovered display timing constants straight from the vendor bootloader's
  live MIPI DSI registers — no public datasheet exists for this exact
  panel-plus-bridge combination.

**The sharp edge:**
- A "golden" capture is only as good as *when* it was taken.
- Every earlier WiFi register harvest turned out to be captured **after**
  the vendor firmware loader had already run — that loader is a
  `core`-class Android init service that fires before any shell is
  reachable at all.
- So months of "known-good" reference data was actually all
  *post-firmware* state — driver work built against it was implicitly
  assuming firmware mainline has no path to load.
- Tried to disable that init service pre-boot to get a true pre-firmware
  capture — blocked by the Android userspace being an LXC container
  rebuilt every boot from a read-only, write-protected image.
- Turned the dead end into a finding: if you can't reach a pre-firmware
  shell, the fair comparison isn't "match the ROM," it's "match the ROM
  after loading the same firmware blob" — which reframes the next
  milestone instead of wasting more time on an unreachable state.

## Where Claude actually helped — and where it didn't

**Investigation:**
- Reading the decompiled vendor device tree, cross-referencing a leaked
  vendor kernel source tree, finding where a GPIO is defined, checking
  whether a symbol exists upstream — wide, shallow search an agent with
  tool access does well and fast.
- Hours of archaeology across scattered vendor source, forum threads, and
  datasheets compressed into minutes.

**Patch quality:**
- A consistent standard (serial observability, complete error paths,
  every hardware value traceable to a cited source) is tedious for me to
  enforce by hand across dozens of patches, and easy for an agent to check
  every time.

**Hardware profile + per-node tests:**
- Claude built and maintained a register-level map of every subsystem:
  address ranges → IP block, which bits the vendor actually sets, which
  values are datasheet-sourced vs. golden-harvest-only, which DTS node
  each maps to.
- `hardware.md` / `driver_ports.md` are that index kept in sync with
  patches as they land — not prose summaries.
- For every DTS entry added, Claude wrote the matching patch *and* an
  isolated test for it — a boot config, a debug trace, or a standalone
  bare-metal harness when a full kernel was too much machinery to isolate
  one register.

**Build/log bookkeeping at scale:**
- 259 build iterations, several hundred more diagnostic captures — each
  with a provenance directory (patch set, `.config`, DTB, sha256, serial
  log).
- Keeping that straight by hand across weeks is exactly where my own
  attention would degrade: same bug as build #187, or a new one wearing
  the same symptom?
- Claude tracking every build against its log, diffing captures on
  demand, and catching an exact repeated signature turned "I think this is
  the same bug" into a checked fact.
- Same for execution: precise, repeatable command sequences (`devmem`/
  `i2cget` peeks, targeted `dmesg` greps, cross-referencing a symbol
  against three source trees) run identically every time — no "did I
  actually run the same test as last time" uncertainty.

**Toolchain note:**
- Kernel builds run inside a QEMU ARM64 VM on a Mac Studio (Apple
  Silicon) — build host, build VM, and target device are all ARM, no
  cross-compilation layer to second-guess.
- Claude drove that VM directly over SSH as routinely as it edited files
  locally.
- The project lives in its own git repo, separate from the kernel tree it
  patches — every patch, every build provenance dir, every revert is
  queryable with ordinary git tooling, not scrollback.

**What it doesn't replace — physical judgment:**
- No static analysis tells you a USB port has no VBUS until someone
  measures it.
- Hard rule: no agent flashes a device's GPT. Every partition write and
  serial capture is a command I run myself, on actual hardware — the
  failure mode of an automated flashing mistake is a bricked device, not
  a failed test.
- Claude's job: reason well about evidence I'm physically gathering,
  propose the next experiment, write it up so the next session doesn't
  re-derive it from scratch.

**What stayed mine — direction:**
- Which subsystem to tackle next, when a fix was "good enough" vs. needed
  more root-causing, when to stop chasing a dead end (the pre-firmware
  capture) rather than force a risky workaround, when a shortcut violated
  the project's own standards.
- Several of the harder root causes in this project only got found
  because I redirected the investigation at the point where the obvious
  next step was actually a distraction from the real bug.

## Where it stands

Build #259 — 259 build-flash-boot-capture iterations since the first
serial byte, each a distinct patch/config/DTS change tested on hardware,
not 259 attempts at the same fix. A typical subsystem takes one clean
build to a dozen, depending on how much is guesswork vs. measurement.

| Subsystem | Status | Difficulty (1-5) | What actually fixed it |
|---|---|---|---|
| Serial console | Working | 2 | UART0 pins/baud triple-sourced from vendor DTB, cmdline, and schematic before touching hardware |
| eMMC storage + rootfs | Working | 2 | Upstream MSDC driver as-is; fresh Debian 13 rootfs replaced the dead 2019 vendor image |
| Display (panel + DDP) | Working | 5 | Three stacked bugs: early-unmasked IRQ hung the *whole system*, then generic MIPI packets ≥0xB0, LK-sourced TIMCON values, vendor-bootloader video timing |
| Keyboard (AW9523B) | Working (base layer) | 3 | I2C expander held in reset, a node hidden with `status="disabled"`, inverted GPIO polarity — three bugs stacked on one driver |
| Charging (BQ25896) | Working | 3 | Charger IC misidentified for years (schematic RT9466, silicon TI BQ25896) — root-caused, wired to mainline `bq25890_charger.c` |
| USB — left port (gadget) | Working | 3 | mtu3 PHY needed vendor-specific session-valid bits forced by hand |
| USB — right port (host, ethernet) | Working | 4 | MUSB config vendor-inaccurate (endpoint count/FIFO table); dual-port broke until left port's leftover host-mode DTS reverted to peripheral |
| Fn/second keyboard layer | Not done | 2 (est.) | Base matrix works; second layer not yet mapped |
| Internal WiFi (CONSYS) | Blocked | 5 | G2a (chip-ID poll) passes; G2b (firmware handshake) fails — needs the vendor firmware blob, capture blocked by a write-protected loop device |
| Bluetooth | Not started | 4 (est.) | Shares the CONSYS MCU with WiFi — blocked on the same firmware question |
| Touchscreen | Not started | 3 (est.) | Same EINT/pinctrl gap as the keyboard's second layer |
| Fuel gauge (battery %) | Deferred | — | MT6351 has no mainline driver; charger-only + userspace voltage monitor accepted as the minimum |

None of this is finished — but "finished" was never really the goal for
me. Maintainable was.
