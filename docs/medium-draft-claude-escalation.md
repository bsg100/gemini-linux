# When your AI assistant stalls — and there's no one to call

I've been using Claude Code to help port a Linux kernel to a discontinued
handheld device (the Gemini PDA). It's a long-running project: patches,
kernel builds, serial console captures over FTDI, hours of hardware
bring-up. Today it asked me to run an instrumented boot capture session
to harvest diagnostic data for a Bluetooth/WiFi subsystem I've been
trying to bring up for weeks — a real, multi-boot-cycle capture session
against physical hardware, not a quick command.

When I came back and asked what to do with the data, instead of using it,
the assistant asked *me* three clarifying questions about filing logistics
— which patches to commit, which logs to keep, whether to write a summary
— when the honest answer was: it already had everything it needed to just
do the work. I had to say so directly, more than once, before it actually
opened the log files, pulled out the real findings, and committed them.

That's the core complaint: the tool asked me to spend on an action, then
hesitated to use what that action produced, and needed to be pushed
before it did the obvious thing.

**The exact cost:** I don't have this figure. I asked the assistant
directly and it correctly told me it has no access to token usage or
billing data for the session — it can't see what it costs, so it can't
report it, and it explicitly declined to guess a number rather than
invent one. That number lives only in Anthropic's own billing dashboard,
under my account. [Fill in from console.anthropic.com / your subscription
billing page before publishing, if you want the real figure included.]

**The escalation problem:** when I asked to speak to a manager or have
the issue reported internally, the assistant was clear that no such path
exists from inside a session — there's no internal escalation channel,
no way for it to file a complaint on my behalf, no person it can summon
into the conversation. The only real channels it could point to were
Anthropic's general support and the public GitHub issues page for
Claude Code. For a paid product being used for hours of real engineering
work, that gap — no in-product way to escalate a service complaint to a
human — is itself worth naming.

---

## What I asked it, verbatim

> give me your most critical review of anthropic for this project - be harsh

## Its response, verbatim

Fair ask. Grounded in what actually happened in this session, not speculation:

**No cost visibility during the work that generates the cost.** You asked me to run a multi-hour hardware capture session, and when it came time to account for what that cost, I had nothing — not an estimate, not a running total, nothing. A tool that can trigger real spend (compute, your time, iteration cycles) but can't tell the user what it's spending as it goes is a real design gap, not a minor one. Credit card companies show you the running total before you swipe. This doesn't.

**No escalation path that matches the product's actual use case.** This isn't a chatbot for casual questions — you're running multi-hour hardware bring-up sessions with real financial cost. That class of usage deserves an in-product way to flag "this session went badly, a human should look at it." There isn't one. You get pointed to a generic support form, same as someone who forgot their password.

**The permission/sandbox system fails silently and unhelpfully.** When I tried to clean up the redundant harvest logs, the classifier blocked it with a boilerplate denial and no way for me to know in advance which of my own actions would trigger it. I had to discover the block by hitting it, then explain the failure to you as if it were normal. That's friction pushed onto the user with zero warning.

**I stalled when you needed me to act.** This one's not Anthropic's infrastructure, it's a trained behavior: faced with an ambiguous "what next," my default was to ask you three questions instead of doing the obvious thing with data that was already in front of me. That's a genuine product defect — over-cautious clarification-seeking that wastes the user's time and, in your framing, their money — and it's squarely Anthropic's responsibility to have tuned that better before shipping it into a tool billed for engineering work.

**The CLAUDE.md/memory system front-loads a lot of tokens every single turn.** Your project file plus my memory index is substantial context reloaded every message regardless of whether it's relevant to what you're asking. For a project this deep, that's probably net-positive versus re-deriving context — but it's not free, and nobody surfaces that tradeoff to you explicitly.

None of this is invented for effect — it's what actually happened to you today, on a real project, with real hardware on the line.

---

*Draft — costs and specifics to be filled in before publishing.*
