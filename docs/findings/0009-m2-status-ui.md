# 0009 — M2: native surfaces for the retinue's status

Date: 2026-11-04 · Ticket: [Where does the player see the retinue's status in game?](../../.scratch/m2-identity/issues/13-native-roster-status.md)
(the decision is there) · Script: `tools/experiments/Retinue_Exp_StatusUI.lua` at `18e2818` · Run files (xz-compressed
JSON) and the crash excerpt: [data/2026-11-04-m2-statusui/](data/2026-11-04-m2-statusui/)

Offline play, mod active, deployed `--statusui`. Save restored from backup `20261104-012215-m2-talkui`. Party: main pawn
Shaira (2283028347), hired Diamonds (743846891, Lv 24, OfflineID `89658ac1-…`) and Folken (1601809365, Lv 27, OfflineID
`426f7888-…`). Sample pawn: Folken.

| Run file | Steps |
|---|---|
| `statusui_20261104_204818` | P1: B1, B2, B3, then B4 (crash) |
| `statusui_20261104_212406` | P2 (marker `p2`), P3 (`p3`), P4 (`p4`), P5 (`p5`) |

## P1 — transient notices

- **B1 `GuiManager.requestNoButtonDialog(String, UInt32)`** (verified-game): shows the given text **centred, on its
  own dark panel**, no buttons. The UInt32 (tried 0, 1, 2, 5) made no visible difference. It does **not** close by
  itself: it was closed by the script's `requestHideDialog()` after 10 s. Text with `—` renders.
- **B2 `requestDispPupUpMessage(Guid, UInt32)` and `requestDispSystemPopupMessage(Guid, Guid[])`** (verified-game):
  the panels show **without any text**, with both the script-owned Guid and the real "Never mind" Guid, although the
  `via.gui.message.get(Guid)` hook was hit and returned the sample text (`subst_hit`; `isExistGuid` false for the
  script Guid). `requestDispPupUpMessage` draws a full-screen panel like the pause-menu background and stays until
  `requestHidePopUpMessage()`; the system popups draw smaller panels over it. Unusable for custom text as called.
- **B3 `GuiManager.reqLevelUp(CharacterID, old, new)`** called alone for Folken with 26 → 27 (verified-game): the
  native level-up notice with Folken's name shows; his level stays 27 (Status page). It only draws.
- **B4 `GuiManager.setTalkBalloonMessage`** (12 args; substituted Guid, `GenderType.Unknown`, nil Wwise / Action
  arguments): **the game's UI hung** and the game had to be killed. REFramework logged an exception in
  `app.ui022901.Item..ctor` ← `ui022901.setMessage` ← `setTalkBalloonMessage`. Not retried; `addTalkSubtitleMessage`
  not tried. No save was written, nothing was lost.

## P2 — talk-menu row (verified-game)

- The fifth row on the root `ShopChoiceNode` (`4c4acb4e-…`) with the label **"Release (Retinue · Lv 27)"** shows in
  full, and picking it ends the talk like Never mind (the selected row 4 rewritten to 3, as in 0007). `·` renders.
- With `_IsDecideEnable = false` ("Adopt — retinue locked"): the row is **drawn like the others (not greyed)**, the
  cursor can rest on it, and confirming it does nothing. The player gets no hint why.
- The Talk sub-menu (node `44dcab9b-…`, "Matters of import" …) gets no extra row.

## P3 — Status page (verified-game)

- Writing the name text after `ui060601_01.setupPawn` (and `PawnInfo2Ref.setup` / `CharaChangeRef.updateName`) shows
  **"Folken · Retinue"** in the page's name header between the Z / C tab keys. Only hired pawns (`CopyOwner._OfflineID`
  non-zero) were marked: Diamonds and Folken yes, the Arisen (Klauss) and the main pawn (Shaira) no.

## P4 — Rift "Previous Hires" (verified-game)

- The list (`ui041401`, flow `PawnList`, SearchId read as `Rehire`) passes each entry through
  `ui041401.ResItem.updateDisp(ResInfo)`, whose `ResInfo` carries **`OfflineId`**, the name and the **level the pawn was
  generated at**, so an entry can be matched to a roster member.
- Writing `TxtPawnName` shows the mark: "★ Folken — Retinue, Lv 23". `★` and `—` render; the game **condenses**
  a long name to fit the column.
- The list shows pawns **currently in the party** too (Folken and Diamonds), at their generation level: Folken Lv 23
  (party Lv 27), Diamonds Lv 22 (party Lv 24). One entry logged with OfflineID zero (a transient refresh with
  Folken's name).

## P5 — adopt confirmation (verified-game)

- `requestDialog` with "Adopt Folken into your retinue?\nGear you give them is lost if they're dismissed or lost." and
  Yes / No: the `\n` breaks the line; both lines fit, centred, without wrapping.
- Opened from the field, the button press again reached the character: A made it jump, and **d-pad down issued the
  "To me" pawn command** (0007 saw only the jump). The answer poll timed out after 60 s without reading an answer
  (the dialog was left open longer while capturing the screenshot).

## Conclusions

1. Custom transient text works through `requestNoButtonDialog(String, UInt32)`; the mod must close it itself.
2. Guid-based popups (B2) do not take substituted text; the pawn speech balloon (B4) crashes when called with nil
   voice objects: neither is a usable surface.
3. Talk-menu rows, the Status page name header and the Rift "Previous Hires" names accept custom text, and the Rift
   entry carries the OfflineID to match it.
4. A disabled talk row looks enabled: it cannot explain why it is disabled.
5. The native dialog fits two lines; input leaks from the field include pawn commands on the d-pad.
