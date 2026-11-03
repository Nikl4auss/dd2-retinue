# 10: Toggle persists in `config.json`

Parent: [M1 spec](../spec.md) (§ `config.json`, § Toggle) · Decision:
[Decide the shape of `config.json` and the M1 mod-menu section](07-config-and-menu-shape.md)

**What to build:** the progression checkbox survives *Reset scripts* and relaunches. Its value lives in Retinue's
`config.json` (`{ "version": 1, "progression": true }`), next to the M2 roster but separate from it. A fresh install
writes nothing until the user changes the setting, and a hand-edited file with mistakes never breaks the mod and is
never silently overwritten.

**Blocked by:** [08: Hired pawns level up](08-hired-pawns-level-up.md)

**Status:** ready-for-agent

- [ ] Read once at script load, written immediately on every change from the menu. `re.on_config_save` is not used.
- [ ] Missing file: defaults (progression on), and no file is created until a change.
- [ ] Per-key resolution: a valid key is used; a missing or wrongly typed key gets its default and a log warning. An
      unparseable file or a non-object top level means all defaults plus a warning, and the file is not overwritten
      until a change.
- [ ] A higher `version` is read for the known keys. On rewrite, unknown keys are kept and `version` is not lowered.
- [ ] The parse and merge logic is pure and tested: missing, valid, wrongly typed key, garbage, higher version, unknown
      keys kept.
- [ ] Verified in game by the user: untick, then *Reset scripts*, and the checkbox is still off.
