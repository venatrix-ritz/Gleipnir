# Evidence: what is known and what is not

Claim tags: **[observed]** read from a real Thor by a read-only command on the stated date; **[src]** a file in a public repository (repo, commit, path); **[unverified]** a guess that has not been checked.

## About the control
- **[observed 2026-10-07]** On Armada `20261006.9c7dd3e` (kernel 7.2.6) the battery supply `battery` has `charge_control_start_threshold` and `charge_control_end_threshold` both reading `0`. A write of `80` to the end threshold is accepted but reads back `0`: the firmware does not use it.
- **[observed 2026-10-07]** The same supply has `constant_charge_current` (writable by root) and `constant_charge_current_max`. The max read `9000000`. The current value read `9000000` at 73 % charge and `4680000` at 96 % while unplugged and discharging: **the firmware changes this value itself**, which is why Gleipnir restores the value it found rather than forcing the maximum.
- **[observed 2026-10-07]** There is no `/sys/class/qcom-battery` directory on Armada. The supplies present are `battery`, `qcom-battmgr-usb`, `qcom-battmgr-wls` and `ucsi-source-psy-pmic_glink.ucsi.01`.
- **[src]** Armada's kernel patch `0903-power-supply-qcom-battmgr-expose-the-charge-current-limit.patch` (armada-os/armada, `packages/kernel/patches/`, read at commit `574da80`, 2026-10-02) exposes the battery manager's `BATT_CHG_CTRL_LIM` as `constant_charge_current` and its commit message says that writing `0` stops the battery charging while the charger keeps powering the system from USB (bypass charging). The same patch makes the attribute writable.
- **[src]** AYN's own Android "Stop at 80 %" works by writing `/sys/class/qcom-battery/limit_capacity_charge`; its "Direct power" option (charger runs the Thor, the battery rests) writes `usb_charge_now` (0 = the charger runs the Thor). This is from the header comment of `Charging.kt` in Thor-Wayfinder/thor-wayfinder (read only; PolyForm Strict; nothing copied), which says it was verified on a Thor on 2026-10-01. Those nodes exist in the Android kernel, not on Armada.
- **[src]** Valve's `steamos-manager` implements "max charge level" through `charge_control_end_threshold` (ACPI SB) or a hwmon attribute (`steamos-manager/src/power.rs`). That is the standard method; it is proven on devices whose firmware honours it, not on the Thor.
- **[src]** MgeeeeK's fork (MgeeeeK/thor-armada, commits `a70010a` and `7e17352`) ships a `thor-charge-limit` script that clamps a `charge_control_limit` node to 1000 µA at 80 % and releases at 77 %. Gleipnir keeps that idea and the thresholds.
- **[src]** Armada issue 363, "Battery charge limit to 80%", was open on 2026-10-07 with Thor owners asking for the feature. Armada does not ship a limiter.

## What follows, and what does not
- The AYN Android feature shows the firmware **can** stop charging at 80 % and run the Thor from the charger. It does not show that Armada's `constant_charge_current` write reaches the same behaviour.
- The patch comment says `0` gives bypass charging; the Armada authors presumably tested it on a device **[unverified: no test result is published in the repository]**.
- Whether the value survives a reboot, and whether the charger supplies the whole system load while clamped, are **[unverified]**.
- So the claim "Gleipnir stops charging at 80 %" is a hypothesis until `gleipnir --test --run` passes on your Thor. The test measures charging stop and charging resume; it does not measure the supply path.

## Open questions
1. Does a clamp of `0` behave differently from a small non-zero value on this firmware?
2. Does the firmware reset the value itself at plug/unplug events?
3. Which power supply reports `online` while charging over USB-C PD? Gleipnir reads `qcom-battmgr-usb`; if it never reads `1` the daemon will never clamp and the test will refuse, listing every supply it saw.
