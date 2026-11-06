# Context

Domain terms as used in code, docs and conversation. Game class names in `code`.
`_Avoid_` lists words not to use for a term in our own prose and identifiers; game identifiers keep the game's naming.

## Pawns

- **Main pawn**: the pawn the player created. Exactly one. Party slot 0 (`app.PawnManager.PawnID.MainPawn`).
  `PawnUtil.isMainPawn` is true; its `Pawn` has a `MainPawnDataContext`.
- **Hired pawn** (game: *sub pawn*): a pawn recruited from the Rift. Party slots 1–2 (`SubPawn01`, `SubPawn02`).
  `PawnUtil.isSubPawn` is true; has a `SubPawnDataContext` (hire time, rental token) and a `PawnOwnerContext`
  (the creator; `CAPCOM` with an `_OfflineID` for game-generated pawns).
  _Avoid_: sub pawn, support pawn
- **Adopted pawn**: a hired pawn the mod has taken ownership of. To the game's save it is still a hired pawn;
  the mod lifts hired-pawn restrictions for it at runtime. Only offline (game-generated) pawns can be adopted.
  An adopted pawn is either **present** (in the party) or **away** (dismissed or lost, still in the roster).
  Between a Return and a successful restore it is **returning**: back in the party, its backup not yet written into it.
- **Roster**: the mod's list of adopted pawns in one save slot, persisted in `reframework/data/Retinue/`. Each save
  slot has its own. At most two: the party is the main pawn plus two adopted pawns. An away pawn keeps its place in
  the roster.
- **Locked roster**: a damaged roster. Nothing is adopted, released or progressed through it, and the mod never
  overwrites it; the player fixes it by hand. A roster written by a newer Retinue is instead **read-only**: its
  pawns still progress, but nothing is adopted or released.
- **Adopt**: add a hired pawn in the party to the roster.
- **Return**: an away adopted pawn hired again from the Rift, by any route; it becomes present again.
  _Avoid_: re-adopt
- **Release**: remove a pawn from the roster; it becomes an ordinary hired pawn again and keeps its level.
  _Avoid_: dismiss (that is the game's action at the Rift)
- **Backup**: the mod's copy of an adopted pawn's progress (level, exp, stat growth, discipline, vocation exp), plus what
  it wore and its skills for display. Mirrors the game while the pawn is present; frozen while it is away.
- **Restore**: writing a pawn's backup back into it on its Return, because the game brings it back at its first-hire
  level. Equipment and skills are never restored.
- **Uninstall guarantee**: removing Retinue leaves every save playable and every pawn an ordinary hired pawn at its
  current level. An away pawn's progress then survives only in its backup, which comes back if Retinue is reinstalled.
- **Save slot**: one of the game's three playthroughs. Each has its own history of autosaves, inn saves and manual
  saves; loading an older one of them rolls that playthrough back. A new game started over a save slot is a different
  playthrough; NG+ over a cleared save slot continues the same playthrough. The game's code calls it a _unit_.
  _Avoid_: save file, slot (alone: ambiguous with party slot), unit (code only)
- **Party slot**: one of the three pawn positions in the party (`PawnManager._PartyPawnList`).

## Identity

- **CharacterID** (`app.CharacterID`, a 32-bit enum value): identifies a pawn's character in the current save.
  Stable across save/load while the pawn stays hired; a re-hired pawn may get a new one or the same one (ticket 19), and a dismissed
  pawn's CharacterID is reused for a different pawn (findings 0006). Never identifies an adopted pawn.
- **Offline ID** (`PawnOwnerContext._OfflineID`, a GUID): identifies a game-generated Rift pawn; unchanged across
  dismiss, lost and re-hire (findings 0006). The roster's key: a pawn without one cannot be adopted.
- **Hire time** (`SubPawnDataContext._HireTime`, seconds of the save's clock as a float): marks one hire. It changes on
  a re-hire and survives save and load (findings 0006); the backup keeps it, in milliseconds. Never identifies a pawn.

## Progression

- **Experience** (`HumanStatusContext.Exp`): progress within the current level, not a running total (verified, findings 0002).
- **Banked experience**: experience a hired pawn keeps accumulating past its level's requirement while the game
  blocks its level-up. Belongs to the game's state, not the mod's; applied as-is once progression is lifted.
- **Discipline** (`JobContext.ConsumableExpProp`): spendable vocation points.
- **Vocation** (game: *job*, `app.Character.JobEnum`): 1 Fighter, 2 Archer, 3 Mage, 4 Thief, 5 Warrior, 6 Sorcerer,
  7 Mystic Spearhand, 8 Magick Archer, 9 Trickster, 10 Warfarer.
  _Avoid_: job, class
- **Vocation rank** (`JobContext.calcJobRank`).

## Lifecycle events

- **Hire**: pawn joins from the Rift (`PawnManager.hirePawn`).
- **Dismiss**: player releases a hired pawn (`PawnManager.dismissPawn`); the game returns items given to it
  (`ItemManager.returnSubPawnItems`).
- **Lost**: a pawn left dead too long leaves the party (`PawnManager.lost`).
