# 29: Exp and next-level on the Status page for members

Parent: [M2 spec](../spec.md) (§ Status (native))

**What to build:** pause > Status shows no exp for an adopted pawn: neither its exp nor what it needs for the next level, and
probably not the vocation rank's either. Members progress like the main pawn, so the page should show it.

**Blocked by:** none (needs a short experiment first).

**Status:** needs-triage

Reported by the user during the ticket 27 checklist run (2026-11-08).

## Notes

- The page type `app.ui060601_01` has its own exp panel: fields `PnlExp`, `TxtExpName`, `TxtExpDetail`, `TxtNext`, `TxtNextJp`,
  methods `setupExp`, `setExp`, `hideExp` (from `tools/dump/out/flat.tsv`). Guess to verify: the game calls `hideExp` (or skips
  `setExp`) for a hired pawn. If so, letting the game's own panel run for a member (skip the hide, or call `setExp` in the post of
  `setupPawn`) beats writing texts by hand.
- Experiment: log which of `setupExp` / `setExp` / `hideExp` run, with their arguments, for the main pawn and a hired pawn; then
  try the panel for a member. Check the vocation tab too (`TxtNextJp`).
- Same fail-closed rule as the marks: a missing method or field leaves the page vanilla.
