# What does the game do to a hired pawn on dismiss, lost and re-hire?

Type: research
Status: open

## Question

From the type dump (`tools/dump/`), `docs/findings/api-map.md`, and other mods' scripts as API reference
(Arisen's Own, any open-source pawn/Rift mods), find out what the code says about:

1. `PawnManager.dismissPawn` / `onDismissPawn`: which contexts are dropped from `ContextDBMS` (status, job, equip,
   `SubPawnDataContext`), and whether the CharacterID is freed or reused.
2. `PawnManager.lost` / `onLost`: what triggers it, what it drops, whether a lost pawn returns to the Rift list.
3. `hirePawn` and the Rift pawn list: where offline (CAPCOM) pawn data comes from, whether a dismissed pawn reappears
   with the same `_OfflineID`, and whether its level/exp/vocation on re-hire come from the Rift data (owner level?)
   or from anything the game kept.
4. Which events or methods are good hook points to detect dismiss, lost and hire for a given pawn.

Mark each finding verified-dump / inferred; the in-game experiment confirms. Feeds the experiment design.
