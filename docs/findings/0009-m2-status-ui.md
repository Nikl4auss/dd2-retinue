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

## P6 — the notice is modal (verified-game, 2026-11-07)

Two throwaway read-only scripts, run by keys (ticket 23). `D` is `GuiManager.Dialog`, `app.ui010101`.

**What the panel does.** `requestNoButtonDialog` is a modal: the world pauses, input is blocked, the HUD hides and Esc is not queued. `MainText` and
`IsNoButton` are ours within one 250 ms sample. After the hide `get_IsDisp` goes false, but `MainText` and `IsNoButton` keep their values.

**It shares the widget with the game's dialogs.**

| Situation | Result |
|---|---|
| hide with a game Yes/No up (save), no notice of ours | closes the game's dialog; the System menu softlocks, only closing the game gets out |
| show with a game Yes/No up | replaces it at once, nothing visible; the hide then softlocks the same way |
| show with the pause menu open | nothing visible, the menu freezes; the hide frees it |
| show, then Esc | the menu does not open; the hide is clean |
| show, then `requestDialog` | the dialog replaces the notice at once (`IsDisp` stays true, `IsNoButton` false) and answers normally; no hide must follow |
| show with the server-error dialog up | ours sits behind it, invisible; the hide does not touch it (separate widget, `NetworkErrorDialog`) |
| show in a talk list | draws over it, the list blocks, the hide frees it |
| show in a cutscene | invisible, the cutscene plays on; the hide is clean |

**What reads each state** (all false in the plain field):

| State | True |
|---|---|
| Pause menu, map, Rift stone menu, Previous Hires | `IsOpenMainFlowUI`, `isPausedGUI`, `PauseManager.isPausedAny` |
| Game Yes/No | `IsDispDialogGui` |
| Server-error dialog | `NetworkErrorDialog.get_IsDisp`, `isPausedAny`; not `IsDispDialogGui` |
| Talk, from its first line to its end | `TalkEventManager._IsTalkingAny` |
| Cutscene | `DemoMediator.get_IsPlayingDemo`, `isDispMovieScreen`; `get_IsPlayingDemo` drops about 0.5 s between two scenes |
| Anywhere in the Rift | `isPausedAny` alone, for the whole visit |

`TalkSelect.IsDisp` sticks after the first talk. `IsMenuUIPause`, `isWaitDialogMessage` and `_IsTalkingManualPlayer` never changed.

**Nothing reads**: scripted talks (Fiska in the prologue), tutorial panels, ambient pawn chatter. A notice there was not tested cleanly; with a tutorial
panel up it did not show and the hide was clean.

**Prompts stay on top**: the interaction prompt (`Hail (Hold to Talk)`, `Examine (Hold)`) stays visible with the panel up and can overlap its text. F on it was not tried.

**Not reached**: a Rift NPC talk, a cutscene after the prologue, a dialog requested by the game itself rather than by script, a notice inside the Rift.

## P7 — exp on the Status page (verified-game, 2026-11-09)

Ticket 29 spike, log-only hooks plus three variants, headless. Script, log and screenshots:
[data/2026-11-09-t29-exp-spike/](data/2026-11-09-t29-exp-spike/). Slot 2: Klauss (Arisen), Shaira (main pawn), Diamonds
(member, Lv 24). No hired non-member in that save.

- A member's Status tab reads "Experience -/ -" and its Vocation tab "Current Discipline -", "Next -". The main pawn's and
  the Arisen's show numbers ("7875/ 14700", "5005 Dcp").
- The texts come from `ui060601_01.setupStatus(CharaData)` and `setupJob(CharaData)`. On a character change the order is
  `setupChara` { `setupStatus`, `setupJob`, `setupPawn`, `setupExp` { `setExp` } }; a tab change runs `setTabId` { `setupExp` }.
- `PnlExp` / `setupExp` / `setExp(StSelData)` are the description box for the row under the cursor (StSelData.Value = row
  index, TitleId/DetailId its title and help). `hideExp` never ran. `TxtExpName`, `TxtExpDetail`, `TxtNext` are null fields.
- The gate is the CharaData's `<IsMainPawn>k__BackingField`: set true in the pre of both methods and back in their post, the
  member shows its own numbers ("Experience 2960/ 17030", "Current Discipline 2078 Dcp", "Next 2922 Dcp"), and the main pawn
  and the Arisen show theirs after a switch. `CopyOwner._OfflineID` := 0 changes nothing. Calling `setupExp` + `setExp` again
  changes nothing.
- Not checked: whether the two methods read the flag for anything beyond these texts.

## Conclusions

1. Custom transient text works through `requestNoButtonDialog(String, UInt32)`; the mod must close it itself.
2. Guid-based popups (B2) do not take substituted text; the pawn speech balloon (B4) crashes when called with nil
   voice objects: neither is a usable surface.
3. Talk-menu rows, the Status page name header and the Rift "Previous Hires" names accept custom text, and the Rift
   entry carries the OfflineID to match it.
4. A disabled talk row looks enabled: it cannot explain why it is disabled.
5. The native dialog fits two lines; input leaks from the field include pawn commands on the d-pad.
6. The notice is modal and shares its widget with the game's dialogs (P6): it may only be shown with nothing else up, and only closed if it is still ours.
7. The Status page hides exp and discipline behind the main-pawn flag of the page's CharaData; setting it for `setupStatus` and `setupJob` alone shows a member's own numbers (P7).
