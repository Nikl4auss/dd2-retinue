# 23: Native notices

Parent: [M2 spec](../spec.md) (§ Status (native): Notices)

**What to build:** the mod tells the player about Returns and roster problems with the game's own centred notice: "<name> returned —
Lv N restored" (or kept, on a guard skip), and once per load when the roster is locked, read-only or the slot unknown.
Every player-facing string lives in one place.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [ ] `requestNoButtonDialog` notice, closed by the mod after 3 s with `requestHideDialog()`, only if it is still the mod's notice on screen.
- [ ] A notice is deferred while a game dialog or menu is up.
- [ ] Pure `labels` module with tests for every string (Return, guard skip, locked / read-only / no slot reasons).
- [ ] Fails closed: missing methods → log only.
- [ ] Verified in game: Return notice shows and closes; a locked roster gives one notice on load.
