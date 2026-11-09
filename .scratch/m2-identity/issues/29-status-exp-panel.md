# 29: Exp and next-level on the Status page for members

Parent: [M2 spec](../spec.md) (§ Status (native))

**What to build:** pause > Status shows no exp for an adopted pawn: neither its exp nor what it needs for the next level, and
probably not the vocation rank's either. Members progress like the main pawn, so the page should show it.

**Blocked by:** none (needs a short experiment first).

**Status:** done

Reported by the user during the ticket 27 checklist run (2026-11-08).

## Notes

- The page type `app.ui060601_01` has its own exp panel: fields `PnlExp`, `TxtExpName`, `TxtExpDetail`, `TxtNext`, `TxtNextJp`,
  methods `setupExp`, `setExp`, `hideExp` (from `tools/dump/out/flat.tsv`). Guess to verify: the game calls `hideExp` (or skips
  `setExp`) for a hired pawn. If so, letting the game's own panel run for a member (skip the hide, or call `setExp` in the post of
  `setupPawn`) beats writing texts by hand.
- Experiment: log which of `setupExp` / `setExp` / `hideExp` run, with their arguments, for the main pawn and a hired pawn; then
  try the panel for a member. Check the vocation tab too (`TxtNextJp`).
- Same fail-closed rule as the marks: a missing method or field leaves the page vanilla.

## Comments

- 2026-11-09: log-only spike sent to the peer session (base `3c457c1`). Part A logs setupExp / setExp(StSelData) / hideExp and the
  setup* calls per character, with PnlExp visibility and the five texts. Part B tries skipping hideExp for a member, then calling
  setupExp + setExp. Slices get planned from its results.
- 2026-11-09, spike on `3c457c1` (headless, by the test session; saves of backup `20261108-122004-m2-t26-pre`: Slot 2, party Klauss,
  Shaira (main pawn), Diamonds (member, present); no hired non-member in that save). Log and screenshots in
  `docs/findings/data/2026-11-09-t29-exp-spike/`. All hooks resolved, no errors.
  - `PnlExp` is not the exp panel: it is the description box at the bottom of the page. `setExp(StSelData)` fills it for the row
    under the cursor (Value = row index, TitleId/DetailId = the row's title and help text, e.g. "Level / A general indicator of
    your prowess"); each cursor move runs `setupExp` → `setExp`, the same for all three characters. `hideExp` never ran.
    `TxtExpName`, `TxtExpDetail` and `TxtNext` are null fields on this page. `PnlExp` stays visible throughout.
  - Order on a character change (Z/C): `setupChara` { `setupStatus`, `setupJob`, `setupPawn`, `setupExp` { `setExp` } }; on a tab
    change: `setTabId` { `setupExp` { `setExp` } }. The arguments are the same for the main pawn and the member.
  - The "-" comes from `setupStatus` (Status tab: "Experience -/ -" for Diamonds, "7875/ 14700" for Shaira) and `setupJob`
    (Vocation tab: "Current Discipline -", "Next -"; after `setupJob` for Diamonds the fields `TxtNextJp`/`TxtTotalJp` are null,
    for Shaira they hold "5005 Dcp"/"8195 Dcp"). Diamonds' CharaData has the data: `CopyStatus` exp 2960, Lv 24, job 3,
    `CopyJob.ConsumableExp` 2078.
  - Variant (a), skip `hideExp`: no effect (never called). Variant (b), `setupExp` + `setExp` after the setup posts: runs without
    error, changes nothing (still "-").
  - Variant (c), `<IsMainPawn>k__BackingField` := true on the member's CharaData in the pre of `setupStatus` and `setupJob`, put back
    in the post: works. Status: "Experience 2960/ 17030" (her own exp; next level at Lv 24). Vocation: "Current Discipline 2078 Dcp"
    (her ConsumableExp), Mage Rank 6, "Next 2922 Dcp" (consistent with Shaira's: rank 7 at 14200 culm exp; 14200 − 11278 = 2922).
    Switching back to Shaira and Klauss shows their own values, no stale panel; the "· Retinue" header stays; no error or freeze.
  - Variant (d), `CopyOwner._OfflineID` := 0 during the same calls: no effect (still "-"). The gate is `IsMainPawn`.
  - One glitch seen once: party HP bars over the page after a REFramework "Reset scripts" by mouse; not seen again with (c) after
    reopening the page, so not caused by it.
  - Not covered: a hired non-member (none in the save); side effects of (c) beyond the page, if `setupStatus`/`setupJob` read
    `IsMainPawn` for anything other than these texts.
- 2026-11-09, `63af8d8`, in-game check (headless, by the test session; mod and probe, no spike; saves of backup
  `20261108-122004-m2-t26-pre`: Slot 2, Klauss / Shaira (main pawn) / Diamonds (member, present)). Evidence in
  `docs/findings/data/2026-11-09-t29-fix-check/`. Backup `20261109-022441-t29-fix` restored after; 7 saves and slots/1, slots/2
  matched by sha256.
  - 1 passes. Status tab: "Diamonds · Retinue", "Experience 2960/ 17030" (the spike's CopyStatus exp 2960). Vocation tab:
    "Current Discipline 2078 Dcp", Mage Rank 6, "Next 2922 Dcp".
  - 2 passes. Two C cycles on each tab: Klauss 7655/ 14700, 8929 / 4721 Dcp; Shaira 7875/ 14700, 8195 / 5005 Dcp; Diamonds
    2960/ 17030, 2078 / 2922 Dcp, every time. Nothing stale, no "-" for Diamonds.
  - 3 passes. Closed the page and reopened it: same values. `status exp: shown for member 89658ac1-…` logged once (02:30:09),
    with no "status exp" report; the Retinue section of the REFramework menu has no "unavailable" line.
  - 4 skipped: hiring a non-member means a trip to the Rift, too long for this run. Not covered.
  - 5 passes. Three weak goblins spawned with Nick's devtools (Enemy spawner) in Vernworth and killed by the party. After:
    Klauss 7982 (+327), 9028 Dcp (+99); Shaira 8187 (+312), 8294 Dcp (+99), Next 4906; Diamonds 3272 (+312), 2177 Dcp (+99),
    Next 2823. Diamonds moves exactly like Shaira (vanilla).
  - 6: no side effect seen. Diamonds' Pawn tab is the vanilla one (Arisen CAPCOM, Pawn Quest "Not Set"); no main-pawn rows or tabs
    appear for her; Shaira's page and numbers are unchanged apart from the fight's gain; the party HUD in the world is normal
    after closing the page.
- 2026-11-09, `63af8d8`, manual pass by the user: all pass, the optional step included. Each character shows its own numbers on
  both tabs, no flicker when switching; a hired non-member still shows "-" (vanilla); the numbers move after a fight. Ticket closed.
