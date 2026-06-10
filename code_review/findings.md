
---

## Full-build validation pass (2026-06-10, VM rebuild)

The rebuilt VM ran the first complete kernel build (`make ARCH=arm64 Image.gz
dtbs modules`, defconfig + kernel.md options + **all ported-driver symbols
enabled**: `GPIO_AW9523B=m`, `DRM_MEDIATEK=m`, `DRM_PANEL_RENESAS_R63419=m`,
`PHY_MTK_MIPI_DSI=m`, `TYPEC_FUSB301A=m`, `REGULATOR_FAN53555=y`,
`CHARGER_RT9467=m`). Two compile-breaking defects found — both **invented
kernel APIs** that no compiler had ever seen because the drivers had never
been built with their symbols enabled:

- **BLOCK (found+fixed) — gpio/0001: fabricated `irq_chip.irq_eoi_list`.**
  `INIT_LIST_HEAD(&aw->irqc.irq_eoi_list)` referenced a field that has never
  existed in `struct irq_chip`. Root cause: the driver used a *mutable*
  per-instance irq_chip with `IRQCHIP_IMMUTABLE` flagged but without the
  required helpers — internally inconsistent. *Fixed properly:* converted to
  the canonical 6.6 immutable idiom — `static const struct irq_chip` with
  `GPIOCHIP_IRQ_RESOURCE_HELPERS`, installed via `gpio_irq_chip_set_chip()`,
  with `gpiochip_disable_irq()`/`gpiochip_enable_irq()` in mask/unmask.
- **BLOCK (found+fixed) — usb/0001: nonexistent `devm_usb_role_switch_get()`.**
  The previous review round's "fix" for the use-after-put WARN substituted a
  devm getter that does not exist in 6.6 (`include/linux/usb/role.h` has no
  devm consumer API). *Fixed:* `usb_role_switch_get()` +
  `devm_add_action_or_reset()` registering `usb_role_switch_put` *before* the
  devm IRQ request, preserving the intended unwind order (IRQ freed first).

Both patches regenerated from the VM tree and re-verified against the clean
Mac checkout. **Final build: 0 errors; `Image.gz` 13,103,697 B;
`mt6797-gemini-pda.dtb` 15,260 B (byte-size-identical to the independent
macOS clang+dtc build); all driver modules link** (`gpio-aw9523b.ko`,
`panel-renesas-r63419.ko`, `fusb301a.ko`, `phy-mtk-mipi-dsi-mt6797.o`,
`rt9467-charger.ko`, mtk DRM stack).

Also discovered during config: **`CONFIG_REGULATOR_MT6351` does not exist —
the MT6351 PMIC has no mainline MFD/regulator/RTC support at all** (only the
ASoC codec). hardware.md corrected; blockers.md B-12. And the 8250 console
symbol is `CONFIG_SERIAL_8250_MT6577`, not `SERIAL_8250_MTK` (kernel.md
corrected).

**Lesson recorded:** "compiles cleanly" claims require the symbol actually
enabled in a full build — added to the pre-merge expectations; the build VM
config now keeps all ported-driver symbols enabled so future builds catch
this class of defect automatically.
