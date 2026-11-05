# How is the uninstall guarantee verified for adopted and away pawns?

Type: grilling
Status: resolved

## Question

M2 promises that removing the mod leaves every save playable and every pawn an ordinary hired pawn. With the M2
decisions in place (roster and backups per save slot under `reframework/data/Retinue/slots/`, the backup written into
the live contexts on Return and kept through save and reload, findings 0008), what exactly must the M2 in-game
checklist in `docs/testing.md` check, and how: for a present member, an away member (dismissed and lost), a member
mid-`returning`, a released pawn, and a slot after a new game / NG+; what "playable" and "ordinary" are checked
against (level, exp, Status page, Rift list, talk menu); what happens to the mod's data folder on uninstall and on a
later reinstall (does an old roster wake up against saves that moved on?); and which of these the checklist runs
with real saves vs. fixture saves.

## Answer

Resolved 2026-11-05 (grilling); every recommendation accepted.

- **Playable**: the save loads and the world is entered; a fight, a save and a reload work; the Rift hires and dismisses;
  no Retinue error or notice appears.
- **Ordinary**: each pawn's level, exp, discipline and Status page equal the probe snapshot taken just before the
  uninstall; the talk menu shows the four vanilla entries (no Adopt/Release); Previous Hires shows plain names (no "★",
  no "Lv"); in a fight a hired pawn gains exp but no level (vanilla rule). The probe stays linked (`--probe`) for snapshots.
- **Per state, after uninstall**:
  - present member: keeps its level and progress, behaves as an ordinary hired pawn;
  - away (dismissed or lost): listed in Previous Hires; re-hired it comes back at its first-hire level, exp 0 (vanilla).
    Its progress lives only in its backup on disk. **Known limit, not a breach of the guarantee**: the guarantee is
    "playable and ordinary", not "progress kept without the mod";
  - `returning`: the save holds it at its first-hire level; ordinary, nothing half-written;
  - released: already ordinary.
- **Data folder**: `reframework/data/Retinue/` (config, `slots/<slot>/` rosters and backups) is never deleted, neither
  by the mod nor by `deploy.sh --remove`. The README says deleting it by hand is the clean uninstall and that doing so
  discards away members' backups.
- **Reinstall after a Return the mod did not see** (revises "How does the mod notice a member leaving and returning, and
  when does it act?" and "How does the mod reconcile the roster with a save that disagrees with it?"): an away member
  **keeps its last `character_id`** in the roster (no longer cleared on dismiss). On load, an away member found in the
  party with the **same** CharacterID is a rollback (save wins, as before); with a **different** CharacterID it was
  re-hired outside the mod's sight → becomes `returning` and is restored under the level guard. The CharacterID still
  never identifies a pawn (OfflineID does); it only tells "same record" from "new record". A chance collision of the
  new 32-bit ID with the old one degrades to "save wins".
- **No uninstall preparation**: no "release all" or "export" action; the guarantee holds when the player just deletes
  the script.
- **New game / NG+ while uninstalled**: nothing is archived (the mod did not see it); on reinstall the old members
  become away by the general rule, take the cap, and the player releases them through the native full-retinue offer.
  Checked *(opportunistic)*, only on a test slot, never on the real playthrough's slot.
- **Only quit → remove → relaunch** is checked; removing the script with *Reset scripts* mid-session is a dev case,
  outside the checklist.
- **Saves for the checklist** (each run preceded by `tools/saves.sh backup`): fixtures for away-dismissed, away-lost,
  `returning` (restore disabled or timed out) and released, and for the Q4 reinstall (re-hire with the mod removed,
  then reinstall: expect restore to the backup's level); the real save for the present member and the final
  "playable" pass.
- Glossary: `CONTEXT.md` gains **Uninstall guarantee**.
