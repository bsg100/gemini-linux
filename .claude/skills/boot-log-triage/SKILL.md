---
name: boot-log-triage
description: Triage a Gemini serial boot log (ftdi-monitor capture) in one token-efficient pass instead of a chain of ad-hoc grep/tail calls. Use whenever the user says "read the serial log" / "flashed and booted" for any boot capture under logs/*.log — kernel bring-up, Kali harvest, or otherwise.
---

# Boot log triage

Runs `scripts/triage-boot-log.py <logfile>` — a single-pass parser that
replaces the usual chain of separate grep calls (banner, panic/BUG scan,
DEVAPC/MPU violation counts, HARVEST- trace counts, reboot detection, tail)
with one compact structured report.

## Usage

```bash
python3 scripts/triage-boot-log.py logs/YYYY-MM-DD-NN-desc.log
```

Options:
- `--tail N` — lines of tail context (default 25)
- `--context N` — lines of context around the first panic/BUG hit (default 12)

## What it reports

- **REBOOTS** — count of `Preloader Start` occurrences; >1 means the
  capture spans multiple boot cycles (common when a build crashes and the
  user power-cycles into the next attempt within the same log file).
- **BANNER** — every `Linux version` line found (confirm it matches the
  build you just flashed before drawing conclusions).
- **MILESTONES** (scoped to the *last* boot cycle only) — whether
  Preloader/kernel-banner/Android-init/userspace-welcome/systemd-finished/
  login-prompt were reached, with line number and kernel timestamp.
- **PANIC/BUG SCAN** — first occurrence of each of: Kernel panic, Internal
  error, Unable to handle (fault), `BUG: failure at`, Oops — with
  `--context` lines around it, `>>` marking the exact line.
- **VIOLATION COUNTS** — DEVAPC and EMI MPU violation occurrence counts
  with first hit location (useful for spotting a violation storm early
  without printing hundreds of repeated lines).
- **HARVEST TRACE** — counts of each `HARVEST-*` instrumentation prefix
  (from the Kali harvest kernel's printk instrumentation, see
  `docs/kali-harvest-plan.md`), if present.
- **TAIL** — last N raw lines, for whatever state the capture ended in.

## When to still read the raw log directly

This triage is a first pass, not a replacement for the raw log. Drop to
`Read`/`grep -a` on the file directly when you need:
- Full context around a *second or third* panic occurrence (triage only
  shows the first).
- The exact byte-level content of `HARVEST-*` hex dumps (triage only
  counts them, doesn't print payloads).
- Anything before the last boot cycle's banner (triage's milestone/panic/
  violation scan is scoped to the last cycle only — pass a shorter log or
  read raw for earlier cycles).

## Note on log encoding

These logs start with a short binary preloader handshake that makes
`file` report the log as "data" and can confuse plain-text tools — the
script decodes with `errors="replace"`, so binary noise renders as
replacement characters rather than crashing. `grep` on these files still
needs `-a` to force text mode.
