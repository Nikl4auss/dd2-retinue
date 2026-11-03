# 0001 — Baseline: how hired pawns behave in the unmodified game

Date: 2026-11-03 · Tool: `tools/probe/Retinue_Probe.lua` (read-only) · Raw data: [data/2026-11-03-probe/](data/2026-11-03-probe/)

Offline play; both hired pawns were game-generated Rift pawns (owner `CAPCOM`).
Other mods were active (no other pawn-progression mod; Arisen's Own already uninstalled).

## Procedure

1. Snapshot with two hired pawns in the party (08:54:38).
2. Fight, snapshot (08:56:11).
3. Save, return to title, load, snapshot (08:57:19).

## Results

| | Main pawn "Shaira" (id 2283028347) | Hired "Alder" (1601809365) | Hired "Clothilde" (1306736823) |
|---|---|---|---|
| Exp: start → after fight → after reload | 3983 → 5874 → 5874 | 0 → 1891 → 1891 | 0 → 1891 → 1891 |
| Level | 16 throughout | 17 throughout | 17 throughout |
| Discipline | 884 → 1363 → 1363 | 0 throughout | 0 throughout |
| Vocation / rank | Archer / 5 | Fighter / 4 | Archer / 4 |
| `PawnUtil.isSubPawn` / `ExpDispenser.isSubPawn` | false / false | true / true | true / true |
| `ContextHolder.IsStore` | true | true | true |
| `ContextHolder.IsRestore` (before → after reload) | true → true | false → **true** | false → **true** |
| `MainPawnDataContext` (on `Pawn` / in holder) | yes / yes | no / no | no / no |
| `SubPawnDataContext` | none | present | present |
| UniqueID | `0000…_-2011938949` | `0000…_1601809365` | `0000…_1306736823` |
| Owner offline ID | zero GUID | `f19dde12-…-9e153f86ee7f` | `f7b3c704-…-3cc21e368ee0` |

`_SavedPartyPawnList` listed the three IDs in party order in every snapshot.

## Conclusions

1. **Hired pawns already accumulate experience**, the same amount as the main pawn (+1891). They do not level up
   and earn no discipline. The block is downstream of experience distribution — consistent with
   `ExpDispenser.isSubPawn` gating `checkLevelUp` / `addJobPoint`.
2. **The game's save persists hired-pawn state** while they stay hired (exp survived reload; `IsRestore` became true).
   Basis for [ADR 0001](../adr/0001-runtime-lift-not-save-injection.md).
3. **CharacterID is stable across save/load.** UniqueID is derived from it.
4. Game-generated pawns carry a unique owner offline ID; candidate for recognising a re-hired pawn.

## Open questions

- Is `Exp` progress within the current level? (Main pawn: 5874 at level 16; hired: 1891 at level 17, started at 0.)
- What happens to the state on dismissal and re-hire? (M2)
- Online pawns (owner with `_UserId`) were not tested; the mod targets offline use.
