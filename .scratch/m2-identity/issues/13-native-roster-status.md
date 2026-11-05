# Where does the player see the retinue's status in game?

Type: prototype
Status: resolved
Blocked by: 11

## Question

Native first: the player must see, without the mod menu, who is adopted, who is away (and why an away pawn's place is
taken), a Return and its restore ("Folken returned — Lv 27 restored" or a guard skip), and a locked or read-only roster.
Using the talk-menu entry from "How should adopt and release look and feel?" and the entry points from "Which native UI
entry points could host adopt and release?", prototype where each message lives (talk menu text, the game's
notification banner, the Status page, the Rift's "previously hired" list) and whether to warn that gear given to an
adopted pawn is lost on dismiss or lost (findings 0008). The mod menu mirrors the same for development and as a fallback.

## Answer

Decided with the user on 2026-11-04, from the prototype run (facts: `docs/findings/0009-m2-status-ui.md`; script
`tools/experiments/Retinue_Exp_StatusUI.lua`). Builds on "How should adopt and release look and feel?" and "How does
the mod notice a member leaving and returning, and when does it act?".

- **Adopted (present)**: the talk-menu fifth row carries the status, "Release (Retinue · Lv N)"; the Status page name
  header reads "<name> · Retinue" for an adopted pawn (only adopted pawns, never the Arisen or the main pawn).
- **Away**: the Rift "Previous Hires" list marks roster members, matched by the entry's `ResInfo.OfflineId`, as
  "★ <name> · Lv N" with the **backup's** level (the list shows the generation level). Ordinary pawns stay unmarked.
  The "retinue full" dialog from the adopt/release ticket stays as decided.
- **Return and restore**: a transient notice through `GuiManager.requestNoButtonDialog(String, UInt32)`, centred:
  "<name> returned — Lv N restored", or on a guard skip "<name> returned — kept Lv M, newer than the backup". The game
  does not close it: the mod closes it after ~4 s with `requestHideDialog()`.
- **Locked, read-only roster or unknown slot**: the same notice once on load, with the reason. The Adopt / Release row
  stays pickable; picking it shows the reason in the same notice and ends the talk like Never mind. No disabled row
  (`_IsDecideEnable = false` draws like an enabled row and just does nothing).
- **Gear warning**: a second line in the Adopt confirmation, "Gear you give them is lost if they're dismissed or
  lost." Dismiss is not touched.
- **Ruled out**: the Guid popups (`requestDispPupUpMessage`, `requestDispSystemPopupMessage`: panels without text), the
  pawn speech balloon (`setTalkBalloonMessage` hung the game; subtitles not tried), the native level-up notice
  (`reqLevelUp` works and only draws, but is not used).
- The mod menu mirrors all of the above, for development and as a fallback.
- **Known risks** for the spec:
  - Unverified whether the notice shows over menus or inside a talk, and whether `requestHideDialog()` would close a
    game dialog open at that moment: the mod closes only a notice it opened and that is still the one displayed, and
    defers a notice while a game dialog or menu is up.
  - Input leaks from the native dialog in the field include the d-pad pawn commands, not only A (the Adopt dialog is
    opened inside the talk, as decided).
  - All texts are literal English strings. The Status page and Rift marks depend on widget fields
    (`PawnInfo2Ref.TxtName`, `CharaChangeRef.TxtName`, `ResItem.TxtPawnName`) a patch can change: fail closed, no mark.
