# 0001 — Lift hired-pawn restrictions at runtime; never inject main-pawn records into the save

Date: 2026-11-03 · Status: accepted

## Context

The game assumes exactly one main pawn. Arisen's Own 1.3.2 makes extra pawns "real" main pawns: it registers
records carrying `app.MainPawnDataContext` in the save database (`app.ContextDBMS`) under fixed CharacterIDs,
replaces large parts of the character creator, and blocks saving whenever its state does not validate.
In practice it breaks easily and leaves saves in states that need its own recovery code.

Probing the unmodified game ([findings/0001](../findings/0001-hired-pawn-baseline.md)) showed that hired pawns already
receive experience and that the game's own save keeps their state across save/load while they stay hired.

## Decision

Adopted pawns remain ordinary hired pawns in the save. The mod changes behaviour only through runtime hooks on
the checks that restrict hired pawns (`isSubPawn` and related), keyed by a roster the mod keeps in its own JSON file.
The mod never writes main-pawn records into the save and never blocks saving.

## Consequences

- Removing the mod leaves a valid save with ordinary hired pawns (keeping whatever level they reached).
- At most two adopted pawns are in the party at once (slot 0 is the main pawn).
- Whatever the game discards for hired pawns (e.g. on dismissal) must be backed up by the mod itself (M2).
- Per-pawn features that only exist for the main pawn (affinity, the creator flow) are out of reach unless a
  later ADR revisits this.
