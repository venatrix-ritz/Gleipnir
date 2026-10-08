# Credits

- **Mragank Shekhar ([MgeeeeK](https://github.com/MgeeeeK/thor-armada))**: the original `thor-charge-limit` script (fork commits `a70010a` and `7e17352`) that this was adapted from: the 80 %/77 % idea and clamping through the battery manager's current limit. His fork ships Armada's `LICENSE.md`, under which original Armada scripts are GPL-2.0-or-later, so `bin/gleipnir` stays GPL-2.0-or-later (terms in `LICENSES/GPL-2.0.txt`).
- **[Armada OS](https://armadaos.dev)** (armada-os/armada): kernel patch `0903`, which exposes the charge current limit as `constant_charge_current`, and the Decky plugin conventions (`flags: ["root"]`) followed here.
- **[Thor-Wayfinder](https://github.com/Thor-Wayfinder/thor-wayfinder)**: its notes on AYN's Android 80 % limit node were read for the evidence page (the code is PolyForm Strict: read only, nothing copied).
- **[SteamOS Manager](https://gitlab.steamos.cloud/holo/steamos-manager)** by Valve: read for the standard `charge_control_end_threshold` method.
- **[Decky Loader](https://github.com/SteamDeckHomebrew/decky-loader)** by the SteamDeckHomebrew community.
- Research on the Thor and Armada this was built from: [venatrix-ritz/AynThor](https://github.com/venatrix-ritz/AynThor).

**Ven** ([venatrix-ritz](https://github.com/venatrix-ritz)): idea, direction, the Thor it is tested against, and every decision about what goes in. Written together with AI assistants (Claude by Anthropic), which are tools, not authors.

If you are named here and want something changed, credited differently or removed, open an issue.
