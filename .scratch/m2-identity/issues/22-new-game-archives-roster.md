# 22: A new game archives the slot's roster; NG+ keeps it

Parent: [M2 spec](../spec.md) (§ Save slot (new playthrough, NG+))

**What to build:** starting a new game (or a restart) over a slot moves its roster and backups to a timestamped archive in that slot
and starts empty; NG+ keeps the roster, and members not in the party become away by reconciliation.

**Blocked by:** [21: The roster reconciles with the loaded save](21-reconcile-on-load.md)

**Status:** ready-for-agent

- [ ] Archive written from the update loop after the hook, never inside it; never deleted.
- [ ] Archive name `archive-<yyyymmdd-hhmmss>` (tested in the `slot` module).
- [ ] NG+ (`RedoNewGameSkip`): roster kept.
- [ ] Verified in game on a test slot (checklist 21, 22, opportunistic).

## Comments

- REFramework likely has no `os.rename` / `os.remove` (the LeovvayGore mod says so; ticket 18's release falls back to
  emptying the file). So the archive is a copy of each file into `archive-<yyyymmdd-hhmmss>/` plus emptying the original
  (an empty file reads as missing).
