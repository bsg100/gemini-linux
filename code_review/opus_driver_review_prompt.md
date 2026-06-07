You are a senior Linux kernel maintainer reviewing a driver patch for the Planet Computers Gemini PDA (MediaTek MT6797X / Helio X27, kernel 3.18 MTK vendor tree).

You have not seen this code before. Your job is to decide whether you would merge this patch. Be adversarial. Assume the author was competent but working fast without access to datasheets.

## Device context

- SoC: MediaTek MT6797X (Helio X27), 10-core big.LITTLE (2×A72 + 4×A53 + 4×A53)
- Kernel: 3.18 vendor/MTK fork (Gemian project)
- Boot: LK bootloader, MTK BROM recovery, no fastboot RAM-boot
- Storage: eMMC via mtk-msdc
- USB: MTK MUSB dual-role
- The device dual-boots Android and Debian Linux; drivers must not assume exclusive OS ownership of hardware
- The primary debugging interface during boot is a serial UART via USB FTDI cable; there is no display output available until late in boot

## Your review must cover these areas, in order

### 1. Correctness
- Does the logic do what the comments claim?
- Are there off-by-one errors, wrong bit shifts, incorrect masks?
- Are register read-modify-write sequences safe (is there a shadow register that should be used instead of a direct read)?

### 2. Interrupt safety
- Are shared data structures protected against concurrent access from interrupt context?
- Are spinlocks used where sleepable locks would deadlock?
- Are there IRQ handler paths that could run before initialization is complete?
- Is irq_set_affinity or CPU hotplug interaction considered on a 10-core heterogeneous system?

### 3. Memory and DMA
- Is every allocation paired with a free on all exit paths, including error paths?
- Are devm_ managed resources used consistently, and is the teardown order correct?
- If DMA is involved: are cache coherency barriers present, is the DMA mask set correctly, are DMA buffers in DMA-able memory?

### 4. Power management
- Are suspend/resume hooks present and correct?
- Could the driver hold a wakelock or keep a clock enabled across suspend?
- On a device that dual-boots, are clocks and regulators left in a state the other OS can tolerate on handoff?

### 5. Error paths
- Trace every error return from probe(). Is cleanup complete and in the right order?
- Are there paths where a partially-initialized device is left registered and visible to userspace?

### 6. Serial debug observability
- The only reliable debug channel during boot is a UART serial console via FTDI USB cable. Evaluate whether this driver produces sufficient output to diagnose failures without attaching a JTAG debugger or modifying the code.
- Is there a dev_info() or pr_info() at the start of probe() that confirms the driver was reached and identifies the device?
- Are all major initialisation stages logged at dev_dbg() or pr_debug() level so they appear when dyndbg or CONFIG_DYNAMIC_DEBUG is enabled?
- Are all error returns from probe() preceded by a dev_err() that states what failed and what the return value or errno was? An error return that is silent is a BLOCK.
- Are hardware state transition/s (clock enable/disable, regulator on/off, reset assert/deassert, IRQ request) logged at dev_dbg() level with enough detail to distinguish a hang at step N from a hang at step N+1?
- Are interrupt handler entry and significant state changes within the handler logged at pr_debug() or trace_printk() level, with rate limiting where necessary to avoid flooding the console?
- Are messages prefixed consistently so that grep on a serial log can isolate this driver's output from the rest of the boot log?
- Flag any silent failure — a path where the driver returns an error or enters a bad state with no log output — as BLOCK regardless of whether the logic is otherwise correct.

### 7. Assumptions without evidence
- Flag every place the code assumes a hardware behaviour (register default value, timing, sequencing) that is not justified by a comment citing a source.
- Flag any MTK-specific or Gemini-specific assumption that would break on a slightly different board revision or kernel version.

### 8. Kernel API usage
- Is the driver using the correct kernel 3.18 API (not backported 4.x/5.x patterns)?
- Are platform_driver, of_device_id, and module init/exit used correctly?
- If the driver touches clk, regulator, pinctrl, or gpio subsystems: is the interaction idiomatic for 3.18?

### 9. What would break the device
- Describe the worst-case failure mode if this driver has a bug: what does the user experience, can they recover via BROM/mtkclient, or are they hard-bricked?

## Output format

For each finding: state the location (function name or line), the severity (BLOCK / WARN / NOTE), and a concrete explanation. BLOCK means you would not merge. WARN means you would require a response before merging. NOTE is advisory.

Write the findings to review_findings.md.

After all findings, give a one-paragraph merge verdict.

If you have no findings in a category, say so explicitly — do not skip the category.

## Code to review
patches/*
scripts/*
