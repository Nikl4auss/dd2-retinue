# 27: Docs, `deploy.sh --probe-only` and the M2 checklist run

Parent: [M2 spec](../spec.md) (§ Uninstall guarantee, § Done when, § Known limits)

**What to build:** the README documents the retinue, uninstalling (the data folder, the clean uninstall) and the known limits; the
roadmap and CHANGELOG are updated; `deploy.sh --probe-only` links the probe without the mod; the M2 checklist in
`docs/testing.md` is run with the user and recorded in a findings note.

**Blocked by:** [16: The mod knows which save slot is loaded](16-save-slot-known.md), [17: Adopt and release from the mod menu; only adopted pawns progress](17-adopt-release-mod-menu.md), [18: Adopted pawns are backed up](18-adopted-pawns-backed-up.md), [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md), [20: A lost member becomes away](20-lost-member-away.md), [21: The roster reconciles with the loaded save](21-reconcile-on-load.md), [22: A new game archives the slot's roster; NG+ keeps it](22-new-game-archives-roster.md), [23: Native notices](23-native-notices.md), [24: Adopt and Release from the pawn's talk menu](24-talk-menu-adopt-release.md), [25: A full retinue offers to release an away member](25-retinue-full-release-away.md), [26: Retinue marks on the Status page and in Previous Hires](26-status-page-rift-marks.md)

**Status:** ready-for-agent

- [ ] `deploy.sh --probe-only`; `--remove` never touches the data folder.
- [ ] README: status, how to adopt/release, uninstall and reinstall behaviour, known limits from the spec.
- [ ] Roadmap and `CHANGELOG.md` (Unreleased → Added) updated; no version bump.
- [ ] Every checklist item passed, opportunistic ones recorded as passed or not reached; findings note written.
