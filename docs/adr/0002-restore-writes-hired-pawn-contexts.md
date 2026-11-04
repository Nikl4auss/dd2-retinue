# 0002 — Restore writes a returned pawn's own hired-pawn contexts

Date: 2026-11-04 · Status: accepted · Ticket: [What does a pawn's backup hold, and when is it written?](../../.scratch/m2-identity/issues/09-backup-contents-and-timing.md)

## Context

[ADR 0001](0001-runtime-lift-not-save-injection.md) keeps adopted pawns as ordinary hired pawns and lifts their
restrictions with runtime hooks. But the game keeps no progress past dismiss or lost: a returning pawn is rebuilt at its
first-hire level, exp 0, with regenerated equipment ([findings 0006](../findings/0006-m2-dismiss-lost-rehire.md)).
Bringing its progress back means writing values into the pawn's contexts, which the game then saves. A reader of
"runtime lift" would not expect the mod to write save state at all.

## Decision

On a Return, the mod writes the pawn's backup into **that pawn's own hired-pawn contexts** (`HumanStatusContext`:
level, exp, stat growth `_IncreaseParams`, extra status boost; `JobContext`: discipline, `CulmativeExp`). Only values
the game itself could have reached for that pawn are written. The mod still never creates main-pawn records, never
creates items, and never blocks saving.

## Consequences

- Removing the mod leaves an ordinary hired pawn at its restored level: the uninstall guarantee of ADR 0001 holds.
- Equipment and skills are recorded but not restored (item creation could duplicate items; skills return unchanged).
- Writing any other context, or values the game could not produce (e.g. a level above the backup's), needs a new ADR.
