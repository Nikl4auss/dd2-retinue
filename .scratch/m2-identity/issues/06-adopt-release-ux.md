# How should adopt and release look and feel?

Type: prototype
Status: resolved
Blocked by: 05

## Question

Choose where and how the player adopts and releases a pawn (and confirms release), from the shortlist in
"Which native UI entry points could host adopt and release?", with the mod menu as fallback. Prototype the
top option(s) roughly enough to react to in game: start from the four probe experiments in the findings
(log the pawn talk menu in the field and at the Rift; rename an option and catch the pick; open the game's dialog
from the mod menu; map a Status-page tab to its pawn). The mod menu stays the complete surface regardless.

## Prototype

`tools/experiments/Retinue_Exp_TalkUI.lua` (menu "Retinue Talk UI (EXPERIMENT)", `./deploy.sh --talkui`), procedure in
`tools/experiments/README.md`. Probes Q1–Q4, plus a fifth talk entry with and without raising `ui021601.DispMax`
(can Adopt/Release be added instead of replacing an existing option?). Run on 2026-11-04: facts in
`docs/findings/0007-m2-talk-ui.md`, run files in `docs/findings/data/2026-11-04-m2-talkui/`.

## Answer

Decided with the user on 2026-11-04, from the prototype run (facts: `docs/findings/0007-m2-talk-ui.md`).

- **Native first (standing preference for M2 and beyond).** Everything the player needs must be doable fluidly in the
  game itself. The REFramework mod menu is a development convenience and a fallback, not a required surface. This
  replaces the earlier "the mod menu stays the complete surface".
- **Adopt / Release is a fifth entry** in the talk menu of a hired party pawn (the root `ShopChoiceNode` that holds
  Dismiss, `_NodeId` `4c4acb4e-…`), appended to the shown list. No existing option is replaced. It is never added to
  sub-menus, and never to the menu of a pawn outside the party (that menu has Hire, not Dismiss). The label is "Adopt" for
  an ordinary offline hired pawn and "Release" for an adopted one.
- **Picking it** asks for confirmation, acts on "Yes", and ends the conversation like Never mind (the picked row is
  rewritten to the Never-mind row before the game maps it, as in step e2).
- **Both Adopt and Release confirm**, with the game's own Yes/No dialog (`GuiManager.requestDialog`, the answer read
  from the dialog widget). It is opened **before the conversation ends**, so the talk keeps the player from acting on the
  button press. Opened from the field, the press leaked to the character (it jumped). Not yet verified inside a talk:
  the implementation checks it first.
  - **Fallback**, if the dialog still leaks input inside a talk: confirm in the talk menu itself, re-shown with
    "Confirm adopt" / "Confirm release" and Never mind.
- **Retinue full**: this only happens when an adopted pawn is away and a newly hired pawn fills its party slot. Picking
  Adopt then opens a dialog: "Your retinue is full." with one button per away member ("Release <name> (away, Lv N)")
  and Cancel. Choosing one asks a second confirmation, "Release <name>? Their progress will be lost." (Yes/No).
  "Yes" releases that member (its backup is deleted) and adopts the current pawn.
- **Ruled out**: replacing "Add to Favorites"; the Status page as an entry point (Q4 shows it can map a tab to a
  pawn, kept only as a known option); replaying the game's own dialogs on the widget (shows nothing).
- **Known risks** for the spec:
  - The labels are literal English strings, not localized.
  - Hooks run on every talk (`newChoiceInfo`, `ui021601.reqDisp`, the update callback). Guild Contracts hooks the
    same talk methods; no clash was seen.
  - The root menu is identified by node id or by its Dismiss choice, which a game patch can change. The mod must fail
    closed: when the node is not recognised, the menu stays vanilla.
