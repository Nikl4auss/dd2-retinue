# 27: Docs, `deploy.sh --probe-only` and the M2 checklist run

Parent: [M2 spec](../spec.md) (§ Uninstall guarantee, § Done when, § Known limits)

**What to build:** the README documents the retinue, uninstalling (the data folder, the clean uninstall) and the known limits; the
roadmap and CHANGELOG are updated; `deploy.sh --probe-only` links the probe without the mod; the M2 checklist in
`docs/testing.md` is run with the user and recorded in a findings note.

**Blocked by:** [16: The mod knows which save slot is loaded](16-save-slot-known.md), [17: Adopt and release from the mod menu; only adopted pawns progress](17-adopt-release-mod-menu.md), [18: Adopted pawns are backed up](18-adopted-pawns-backed-up.md), [19: Dismiss and Return restore an adopted pawn's progress](19-dismiss-return-restore.md), [20: A lost member becomes away](20-lost-member-away.md), [21: The roster reconciles with the loaded save](21-reconcile-on-load.md), [22: A new game archives the slot's roster; NG+ keeps it](22-new-game-archives-roster.md), [23: Native notices](23-native-notices.md), [24: Adopt and Release from the pawn's talk menu](24-talk-menu-adopt-release.md), [25: A full retinue offers to release an away member](25-retinue-full-release-away.md), [26: Retinue marks on the Status page and in Previous Hires](26-status-page-rift-marks.md)

**Status:** done

- [x] `deploy.sh --probe-only`; `--remove` never touches the data folder. (`173d69a`, `5103ea5`)
- [x] README: status, how to adopt/release, uninstall and reinstall behaviour, known limits from the spec.
- [x] Roadmap and `CHANGELOG.md` (Unreleased → Added) updated; no version bump.
- [x] Every checklist item passed, opportunistic ones recorded as passed or not reached; findings note written.

## Comments

Load-only part of checks 23–26 (2026-11-06, Slot 2, fixture `m2-adopted-folken`, run by another Claude session with `tools/autotest/run_load.sh`, no user; output in `docs/findings/data/2026-11-06-m2-load-checks/`, `<run>.txt` plus hashes in `.before`/`.after`). All eight matched. Only the log and files are covered: the fights, dismisses, talk rows and notices of these checks are still to run, so none of 23–26 is passed yet.

- 24, `status: banana` (A): warning, then `roster away ... → present, save wins`, no restore, roster `present`.
- 24, `name: 5` (B): warning `using (unknown)`, name refreshed to Folken, no correction.
- 25, `version: 2` (C): `roster read-only: written by a newer Retinue (version 2)`, nothing under `slots/2/` changed.
- 25 with `away` (D): the correction logged, roster and backup unchanged on disk (in memory only).
- 23, `not json` (E): `roster locked: not valid JSON ...`, no pass, nothing changed.
- 23, three members (F): `roster locked: more than 2 members ...`, no pass, nothing changed.
- 26, present member (G): `backup of Folken: damaged: not valid JSON`, no correction, file rewritten at Lv 28 by the end of the run (16 s in the world; the moment was not measured).
- 26, `returning` (G2, stands in for the away → Return case): `returning→present skipped: no backup (damaged: not valid JSON)`, roster `present`, file rewritten at Lv 28.
- 2026-11-07, from ticket 23: decide whether to keep the notice diagnostics added in `83b4485`, namely the `notice state`
  lines on every change while a notice waits or shows, and the "Close notice (game stuck)" menu button (it hides the
  shared dialog, a game dialog included). The freeze they were added for, on `0b9de66`, did not reproduce.
- 2026-11-08, decided (user approved the plan): the per-change `notice state` lines are dropped; the one log line per show,
  hide and drop and the "Close notice (game stuck)" button stay.
- 2026-11-08, checklist run on `32074a4`: every item passed or recorded as not reached, in
  [findings 0011](../../../docs/findings/0011-m2-checklist-run.md). Headless runs A–F by the peer session; checks 2, 14, 17, 27, 34 and
  the free play by the user. New ticket 29 (exp on the Status page) from the user's play.
