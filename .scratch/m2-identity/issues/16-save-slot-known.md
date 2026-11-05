# 16: The mod knows which save slot is loaded

Parent: [M2 spec](../spec.md) (§ Save slot, § Code layout and tests)

**What to build:** the mod tracks which save slot (the game's unit) the player has loaded, from the start or load request, and falls
back to `LastLoadedSlot`/`UnitNumber` only when both agree. The *Retinue* menu shows `Slot N` (1–3, as the player sees
them) or `Slot unknown`. Before adding M2 glue, the REFramework-facing code of the entry script is split into thin
game-facing modules so later tickets add to them rather than to one growing file (prefactor, no behaviour change).

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Prefactor first, M1 behaviour unchanged: all existing tests pass and the M1 menu looks the same.
- [x] `requestLoadGameData` pre sets the unit from the global slot ÷ `SLOT_PER_UNIT` (read from `app.GameSystem` at runtime, never hard-coded); `requestStartType(NewGame)` pre sets it from `UnitNumber`.
- [x] Fallback in the world only when no such call was seen this session, and only when `LastLoadedSlot ÷ SLOT_PER_UNIT` equals `UnitNumber`; otherwise unknown.
- [x] `StartType` classified as new playthrough (`NewGame`, `RedoNewGame`), NG+ (`RedoNewGameSkip`) or load; the classification is exposed for later tickets (no archiving yet).
- [x] Pure `slot` module with tests: unit arithmetic, fallback rule, classification, directory name (`slots/<unit + 1>`), archive name.
- [x] Hooks fail closed: a missing method leaves the slot unknown, logged once.
- [x] Verified in game: the menu shows the right slot after a title load, a Continue, a death reload and a load from another slot.

## Answer

Shipped in `c33ef8c` (prefactor into `src/autorun/Retinue/game/`), `8d3ddae` (pure `slot.lua` + tests, slot hooks,
fallback, menu line) and `5d4cc80` (the session also counts load requests, for ticket 21's one-pass-per-load). Plan:
[../plan.md](../plan.md). The session exposes `unit`, `source`, `seen`, `last_start`, `starts`, `loads`.

In game (2026-11-05, user): slot 1 load → `Slot 1`; slot 2 load → `Slot 2`; death reload in slot 2 → `Slot 2` kept;
relaunch and load last save → `Slot 2`; *Reset scripts* in the world (fallback) → `Slot 2`.
