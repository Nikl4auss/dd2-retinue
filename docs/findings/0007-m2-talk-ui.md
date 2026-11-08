# 0007 — M2: the party-pawn talk menu, the native dialog and the Status page

Date: 2026-11-04 · Ticket: [How should adopt and release look and feel?](../../.scratch/m2-identity/issues/06-adopt-release-ux.md)
(the decision is there) · Script: `tools/experiments/Retinue_Exp_TalkUI.lua` at `283c2be` (reworked between runs:
`fd871f0`, `1a841f9`, `bacf58e`) · Research input: `research-m2-native-ui.md` (branch `research/m2-native-ui`) · Run
files (xz-compressed JSON): [data/2026-11-04-m2-talkui/](data/2026-11-04-m2-talkui/)

Offline play, mod active, deployed `--talkui`. Party: main pawn Shaira (2283028347), hired Diamonds (743846891) and
Folken (1601809365). Other mods hooking the same talk methods were active (Guild Contracts hooks `newChoiceInfo` and
`startNode`); nothing clashed.

| Run file | Steps |
|---|---|
| `talkui_20261104_012322` | Q1: talk to Folken in the field, then at a Rift stone |
| `talkui_20261104_093427` | panel check after the rework (radio-button error) |
| `talkui_20261104_093808` | Q2 a–e (markers `a`..`e`) |
| `talkui_20261104_094955` | Q2 e2 (fifth entry with the widget-level redirect), Q3 first try |
| `talkui_20261104_095949` | Q3 with widget answer, captured replay; Q4 |

## Q1 — the menu (verified-game)

- Talking to a hired party pawn gives the **same menu in the field and at a Rift stone**: Talk / Dismiss / Add to
  Favorites / Never mind. It is **not** a `PawnRentalNode` (as the research inferred) but an **`app.ShopChoiceNode`**
  (`_NodeId` `4c4acb4e-1531-45ea-9f6a-e4152e473e2e`, NodeType `ShopChoice`, name `ショップ用選択肢ノード05`) with
  **10 choices**, 4 shown by display conditions. Choice index → next node: 0 Talk (`ショップ用選択肢ノード02`),
  1 delivery, 2 itself, 3 camp cooking, 4 pawn talk 16, 5 rift powder, **6 Dismiss** (`解雇`, ChoiceId `7d3962d3…`),
  **7 Add to Favorites** (`お気に入り登録`, `4e9a6ef3-e678-423b-ac7f-3f6a13fa9a90`), 8 Remove from Favorites
  (`お気に入り解除`, `15b8029d…`), **9 Never mind** (`終了`, `cde9623d-2e45-424a-b326-daa8c3b7078c`). The node is
  reached from a `PawnTalkNode` (greeting); speaker = the pawn, listener = the Arisen.
- The shown list is built by `TalkEventPlayer.newChoiceInfo(Guid, Bool×4)` (one call per shown entry, in display order,
  returning a `ui021601.ListInfo` with `Msg` = the English text) and handed **straight to `ui021601.reqDisp`**:
  `GuiManager.requestTalkSelect`, `startPawnRentalNode` and `startChoiceNode` never fire. `ListInfo.Listener` is nil
  here (it is the Rift rental info, not used by this menu).
- `ui021601.DispMax` is **8** (not 4 as Guild Contracts saw for Freki's menu).
- `TalkEventPlayer.nextNode(Int32)` receives the **index into the node's `_Choices`** (9 for Never mind), not the row on
  screen. It also fires with 0 for every linear node.
- The user also observed: talking to a pawn **not** in the party gives the same menu with **Hire** instead of Dismiss.

## Q2 — relabel, catch, redirect, a fifth entry (verified-game)

- **Relabel** works by both paths: `newChoiceInfo` post, matching the Guid and writing the returned `ListInfo.Msg`;
  and writing `Msg` of the list entry in `ui021601.reqDisp` pre. The row reads "Adopt".
- **Catch**: `nextNode` pre sees index 7 for the relabelled Favorites row. Without redirect the game still runs
  Favorites (pawn added to favourites; the row then becomes "Remove from Favorites", choice 8, which the Guid relabel
  does not touch).
- **Redirect**: rewriting the `nextNode` argument 7 → 9 ends the conversation cleanly, exactly like Never mind.
- **Fifth entry**: a new `ListInfo` (`sdk.create_instance` + `.ctor`, `Msg`, `_IsDecideEnable = true`, types copied from
  entry 0) appended to the list in `reqDisp` pre **is shown** as a fifth row, without touching `DispMax`.
  - Picking it unhandled: the game calls **no** `nextNode` and the talk ends (by an unknown path; not safe to rely on).
  - `GuiManager.getTalkSelectSelectedIndex` and `ui021601.getSelectedIndex` cannot be hooked (REFramework logs
    `Cannot add nullptr function`; they never fire). `ui021601.reqEnd` fires once per decision with `SelectedIndex` set.
  - Handled: once `ui021601.get_IsEndGUI()` is true with `SelectedIndex` on the appended row, writing
    `SelectedIndex` = the Never-mind row (3) **before the game maps it** (caught at the start of `UpdateBehavior`; also
    tried in `updateChoiceNode` pre and `reqEnd` pre) makes the game run Never mind (`nextNode(9)`): clean end. A normal
    pick afterwards (Talk and its sub-menu) behaves normally.
  - The prototype appended the entry to **every** menu while talking to the pawn, including Talk's sub-menu: the real
    mod must append only on the root node above (match `_NodeId`, or the presence of the Dismiss choice).

## Q3 — native dialog (verified-game)

- `GuiManager.requestDialog(String ×5, …)` (21 args) called from the update callback with main text, `"Yes"`, `"No"`
  and every other argument false / 0 / nil / 0.0 **opens the game's dialog** with those two buttons.
- The answer: `GuiManager.getDialogState()` stays `None` until the game itself calls `ui010101.getRetVal` (it does, a
  frame after the pick); the widget (`GuiManager.Dialog`, `app.ui010101`) has it at once in `Ret` and
  `getRawRetVal()`: **`SelYes` = 1, `SelNo` = 2**. `IsDispDialogGui()` goes false right after.
- **Input leaks**: opened from the field, the A press that picks a button also reaches the player character (it jumps).
- The game's own yes/no dialogs (save, return to title) go straight to `ui010101.reqDisp` (24 args; system dialogs pass
  empty button texts, an int 40 and -1, and two `true` flags) and never through `requestDialog`. Replaying a captured
  call on the widget shows **nothing**; it bypasses the GuiManager dialog queue.

## Q4 — Status page (verified-game)

- `ui060601_01.setupPawn(GUIBase.CharaData)` fires on every tab change with the tab's character: `CharaId`,
  `IsMainPawn`, `CopyOwner._OfflineID` (zeros for the Arisen and the main pawn), owner name `CAPCOM` for offline pawns.
  The Arisen goes through `setupPawn` too. `setPawnData` never fired; `partyListCtrlSelectionChangedIsPC` and
  `setTabId` fired.

## Follow-up — the mod's talk-menu row (ticket 24, 2026-11-08, verified-game)

Three headless runs (gamescope, XTEST keys, F taps of 0.2 s; no pad) on the mod, Slot 2, party Shaira / Diamonds / Folken.

- Reading the root node at `ui021601.reqDisp` pre in the mod: `_NodeId` (raw-qword GUID read) and the speaker CharacterID
  read fine, but **`get_elements()` fails on the node's `_Choices`**; read by index it gives the 10 choices, Never mind last.
  The mod now reads it by `get_Count`/`get_Item`, then `get_Length`/`GetValue` (`04f7aff`).
- `GuiManager.TalkSelect:get_address()` equals the raw `this` of the `reqDisp` hook: the identity check holds.
- With the row picked, the redirect to Never mind and `requestDialog` in the same `UpdateBehavior`: the dialog shows within
  0.3 s, and **by then the talk is over** (HUD, party list and the `Hail (Hold to Talk)` prompt are back behind it). No
  flicker, no second dialog.
- **No input leak** on 4 confirms (2 Yes, 2 No) with F taps: no jump, no attack, no interaction, no pawn command. Untested:
  the pad's A, and F held about 1 s on the dialog (the Hail prompt is live under it).
