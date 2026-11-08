# M2 plan: ticket 27 (docs, `deploy.sh --probe-only`, the M2 checklist run)

Source: [issues/27-docs-probe-only-checklist-run.md](issues/27-docs-probe-only-checklist-run.md), [spec.md](spec.md) § Uninstall
guarantee, § Done when, § Known limits; checklist `docs/testing.md` § M2. Base commit: `381ad12`.
(Plans of earlier tickets are in git history.)

Cross-review: skipped (Sol and Astra unavailable on this account); Opus `reviewer` only.

- [x] Slice 1: `deploy.sh --probe-only`. Tier: **Opus, inline** (19 lines). Commit `173d69a`. Exercised on a fake `DD2_DIR`.
- [x] Slice 2: README, CHANGELOG, roadmap. Tier: **Opus, inline**. Commit `5103ea5`. One review round: 1 should (M1 wording in
  Compatibility) and 9 nits applied; skipped: rewording the M1 Added entries (the Changed entry covers it).
- [x] Slice 3: notice diagnostics from ticket 23 (`83b4485`): the per-change `notice state` lines dropped; the per-action log
  line and the "Close notice (game stuck)" button kept. Tier: **Opus, inline** (12 lines removed).
- [ ] Slice 4: the checklist run on the final build (peer headless + the user), recorded in `docs/findings/0011-m2-checklist-run.md`.
- [ ] Slice 5: close ticket 27; README status and roadmap say M2 done.

## Slice 4: the run

Coverage before the run (from the ticket comments, 16-26): see the table in the findings note once written. Rule: a pass on a build
whose later changes do not touch the check stands; a check is re-run when a later ticket changed its path, it was only partial, or it
was never run.

Fixture fix: `docs/testing.md` Setup names `fixture-2hired-at-rift` and `fixture-1hired-1slot-free`, which no longer exist. Use
`m2-adopted-folken` (`20261106-083816`, Folken Lv 28 + a second hired pawn) with `slots/` moved aside for check 1, and fix Setup.

**Peer (headless, keys only, `tools/autotest/run_load.sh` style):** load-and-check, hand-edited files, uninstall and reinstall.
- 1 (fresh install: no `slots/`, empty roster on load), 18 (adopt in slot A via talk, load slot B, back to A),
- 23 rest (locked: talk row shows reason and ends talk; three members in game), 24 (warning in menu/log after notices),
  25 rest (dismiss under read-only, files unchanged), 26 rest (real away member with damaged backup, Return, rewrite timing),
- 27, 28, 29 (title-load variant, notice), 31 with `--probe-only`; 10/12 re-run on HEAD (dismiss, Return, `m2-b` vs `m2-a`).

**User (manual, guide inline in Spanish):** anything with fights, *Grant exp* (lifecycle panel, mouse), feel, other mods.
- 2 at a Rift stone, 5 and 6 on HEAD, 7 "no longer levels", 8 menu lists two, 14 (*Kill pawns* + no false absence) on HEAD,
  17 gear, 19 rollback on HEAD, 34 Guild Contracts, and the feel pass of the whole flow.
- Opportunistic, record passed or not reached: 9, 16, 22 (ticket 28), 29b same-ID, 32, 33 Rift-menu variant.

Stands from earlier runs: 3, 4, 11, 13, 15, 20, 21, 33 (base), 30 (via 20c + 28).
