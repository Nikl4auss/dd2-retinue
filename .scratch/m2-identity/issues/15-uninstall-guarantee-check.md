# How is the uninstall guarantee verified for adopted and away pawns?

Type: grilling
Status: open

## Question

M2 promises that removing the mod leaves every save playable and every pawn an ordinary hired pawn. With the M2
decisions in place (roster and backups per save slot under `reframework/data/Retinue/slots/`, the backup written into
the live contexts on Return and kept through save and reload, findings 0008), what exactly must the M2 in-game
checklist in `docs/testing.md` check, and how: for a present member, an away member (dismissed and lost), a member
mid-`returning`, a released pawn, and a slot after a new game / NG+; what "playable" and "ordinary" are checked
against (level, exp, Status page, Rift list, talk menu); what happens to the mod's data folder on uninstall and on a
later reinstall (does an old roster wake up against saves that moved on?); and which of these the checklist runs
with real saves vs. fixture saves.
