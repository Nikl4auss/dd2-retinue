# 16: The mod knows which save slot is loaded

Parent: [M2 spec](../spec.md) (§ Save slot, § Code layout and tests)

**What to build:** the mod tracks which save slot (the game's unit) the player has loaded, from the start or load request, and falls
back to `LastLoadedSlot`/`UnitNumber` only when both agree. The *Retinue* menu shows `Slot N` (1–3, as the player sees
them) or `Slot unknown`. Before adding M2 glue, the REFramework-facing code of the entry script is split into thin
game-facing modules so later tickets add to them rather than to one growing file (prefactor, no behaviour change).

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Prefactor first, M1 behaviour unchanged: all existing tests pass and the M1 menu looks the same.
- [ ] `requestLoadGameData` pre sets the unit from the global slot ÷ `SLOT_PER_UNIT` (read from `app.GameSystem` at runtime, never hard-coded); `requestStartType(NewGame)` pre sets it from `UnitNumber`.
- [ ] Fallback in the world only when no such call was seen this session, and only when `LastLoadedSlot ÷ SLOT_PER_UNIT` equals `UnitNumber`; otherwise unknown.
- [ ] `StartType` classified as new playthrough (`NewGame`, `RedoNewGame`), NG+ (`RedoNewGameSkip`) or load; the classification is exposed for later tickets (no archiving yet).
- [ ] Pure `slot` module with tests: unit arithmetic, fallback rule, classification, directory name (`slots/<unit + 1>`), archive name.
- [ ] Hooks fail closed: a missing method leaves the slot unknown, logged once.
- [ ] Verified in game: the menu shows the right slot after a title load, a Continue, a death reload and a load from another slot.
