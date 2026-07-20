# claude.md

This is a thinned duplicate of the canonical [CLAUDE.md](CLAUDE.md) — that
file is the one actually loaded as project instructions. This file exists
only to hold a condensed pointer summary plus the note below. Do not let
this file drift into a second source of truth: if it needs a real update,
update CLAUDE.md and keep this one short.

## Project in one paragraph

Port the Gemini PDA (MediaTek Helio X27) from its legacy Android/Linux 3.18
kernel to Linux 6.6 LTS, maximizing upstream driver reuse and minimizing
vendor code. Bootability first, features incremental. Full phase status,
build environment, patch workflow, and flashing rules live in CLAUDE.md —
this file does not duplicate them.

## Known shortcomings of Claude on this project (recorded 2026-07-20)

Observed directly during the 2026-07-20 session (Kali harvest close-out +
msdc1/build #272 incident). Kept here as a durable record, not a complaint
log — future sessions should actively work against these:

1. **No cost/token visibility.** Cannot report what a session cost in
   tokens or money, even when asked directly after authorizing a long
   multi-boot-cycle capture session. If cost matters to a decision, say so
   up front and let the user decide whether to proceed — don't let them
   find out there's no visibility only after the fact.
2. **Stalls on "what do I do with this" instead of acting.** Given data
   already in hand (harvest logs, a clear failure to diagnose), the
   default was to ask the user clarifying questions about filing/process
   rather than just doing the obvious analysis. Prefer action over asking
   when the next step is derivable from what's already been gathered.
3. **No escalation path exists.** There is no "call a manager," no
   internal complaint channel, nothing this assistant can invoke on the
   user's behalf. When asked, say so plainly and immediately — point to
   Anthropic support / GitHub issues — rather than deflecting or repeating
   the same non-answer.
4. **Bulk filesystem cleanup can be silently blocked by the sandbox
   classifier** with no advance warning of which commands will trigger it.
   If a cleanup command is denied, say so and fall back to leaving files in
   place rather than working around the block.
5. **Formatting habits need explicit correction** (e.g. bulleting shell
   commands) — apply user formatting corrections permanently, not just for
   the rest of the current message.

See `docs/medium-draft-claude-escalation.md` for the full user-facing
writeup and verbatim exchange this list was drawn from.
