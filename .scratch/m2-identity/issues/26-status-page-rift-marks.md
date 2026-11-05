# 26: Retinue marks on the Status page and in Previous Hires

Parent: [M2 spec](../spec.md) (§ Status (native))

**What to build:** the Status page header reads "<name> · Retinue" for a present member, and the Rift's Previous Hires list shows
"★ <name> · Lv N" (backup's level) for every member.

**Blocked by:** [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md)

**Status:** ready-for-agent

- [ ] Status page: only members, never the Arisen or the main pawn.
- [ ] Previous Hires matched by `ResInfo.OfflineId`; ordinary entries untouched.
- [ ] Fails closed when a widget field is missing (no mark, logged once).
- [ ] Verified in game (checklist 4, 11).
