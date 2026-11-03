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
- **Roster**: the mod's list of adopted pawns, persisted in `reframework/data/Retinue/`. At most two: the party is
  the main pawn plus two adopted pawns. An away pawn keeps its place in the roster.
- **Adopt**: add a hired pawn in the party to the roster.
- **Release**: remove a pawn from the roster; it becomes an ordinary hired pawn again and keeps its level.
  _Avoid_: dismiss (that is the game's action at the Rift)
- **Party slot**: one of the three pawn positions in the party (`PawnManager._PartyPawnList`).

## Identity

- **CharacterID** (`app.CharacterID`, a 32-bit enum value): identifies a pawn's character in the current save.
  Stable across save/load while the pawn stays hired.
- **Offline ID** (`PawnOwnerContext._OfflineID`, a GUID): identifies a game-generated Rift pawn; candidate key for
  recognising the same pawn after it was dismissed and re-hired (unverified).

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
