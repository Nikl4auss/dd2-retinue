# 0005 — M1 in-game checklist run

Date: 2026-11-03 · Checklist: [testing.md § M1](../testing.md#m1--progression) · Ticket:
[12](../../.scratch/m1-progression/issues/12-docs-and-m1-checklist-run.md) · Mod code at `e9c5a9a` (docs `c02eee5`) ·
REFramework `d4611aef` · Probe snapshots: [data/2026-11-03-m1-checklist/](data/2026-11-03-m1-checklist/)

Offline play. Backup `20261103-184924-m1-checklist`. Deployed with `./deploy.sh --probe` (mod + probe, no
experiment script); no `config.json` at the start. Party: main pawn Shaira (2283028347), hired Clothilde
(1306736823, Archer) and Diamonds (743846891, Mage); Folken (1601809365) hired at check 9 in place of Clothilde.
No other mod's exp multiplier was changed during the run.

## Results

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | Menu, fresh install | **Pass** | Box ticked, no `Progression unavailable`, `Applies to:` with both hired pawns; no `config.json` created |
| 2 | Banked exp | **Pass** (via check 8) | No pawn had banked exp at the start (each one's exp below its next-level requirement). Exp banked while off (check 7) was applied at check 8 |
| 3 | Normal fight | **Pass** | `185656` → `190138`: all three +360 exp, +58 discipline. `190138` → `190413`: all +1770 exp, +290 discipline; Diamonds 22 → 23 with one notification naming Diamonds; the player's own rank-up notification named the player |
| 4 | Hired-pawn rank-up | Not reached | The situation did not come up (confirmed earlier, ticket 09 / findings 0003) |
| 5 | Save → title → load ×2 | **Pass** | No freeze either time; `191054` identical to `190413` |
| 6 | Full relaunch | **Pass** | `191500` identical; menu state unchanged; no Retinue line in the log |
| 7 | Toggle off | **Pass** | `config.json` = `{"progression": false, "version": 1}`. `191500` → `193005`: all +10 889 exp; hired pawns no discipline, no level; main pawn +905 discipline, rank 6 → 7. Still off after *Reset scripts* |
| 8 | Toggle on again | **Pass** | Clothilde had 16 521 exp at level 21 (13 580 needed, so banked). `193005` → `193356`: 21 → 22 with 3281 left (= 16 521 + 340 − 13 580); one notification with her name, shown after the fight ended |
| 9 | Party change | **Pass** | Clothilde dismissed, Folken hired: the status line showed him without *Reset scripts*; `194119` → `194244`: Folken +210 exp, +66 discipline, like the others |
| 10 | Malformed config | **Pass** | `not json`: defaults, warning in menu and log, file untouched until a toggle (ticket 10). `{"version":1,"progression":"yes","extra":1}`: progression on, log `[Retinue] config.json: progression is missing or not a boolean; using true`, menu warning; after tick/untick/tick the file kept `"extra": 1` |
| 11 | Main pawn untouched | **Pass** | In every snapshot Shaira moved only by her own grants; her notifications named her |
| 12 | Mod-originated grant | Not reached | No such grant came up |
| 13 | SkillCreator refund rank-up | Not reached | Did not come up |
| 14 | SDT multiplier ≠ 1 | Not reached | Preset not changed |
| 15 | Uninstall | **Pass** | `./deploy.sh --remove`, relaunch, load: the save loads; Diamonds (Lv 24) and Folken (Lv 23) keep their levels |

## Observations

- **Notifications are deferred to the end of combat** by the game: a level-up during a fight (Clothilde, check 8)
  shows its notification once the fight ends, not when it happens. Vanilla behaviour, the same for every recipient.
- **CharacterIDs are reused**: Folken has 1601809365, the ID Alder had in findings 0002/0003. Harmless for M1 (party
  read every frame), but M2's roster cannot key on CharacterID alone; the offline ID is the candidate (`CONTEXT.md`).
- **NickCore sets the global log level to `error`**, which hid `log.warn`. Found before this run; config warnings are
  now in the menu and logged as errors (`e9c5a9a`).

## Conclusion

Every non-opportunistic check passes; checks 4, 12, 13 and 14 were not reached. No failure, so no new ticket. M1 is
done.

## Open questions

- Check 12 (`sdk.hook` firing for Lua `method:call`, e.g. UDD2P's Sphinx reward) remains unverified.
