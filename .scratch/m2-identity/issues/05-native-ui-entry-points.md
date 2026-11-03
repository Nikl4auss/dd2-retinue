# Which native UI entry points could host adopt and release?

Type: research
Status: resolved

## Question

Adopting should feel native, with the REFramework mod menu as baseline and fallback. From the type dump and other
mods that add or alter in-game UI (GUI menus, talk/interaction options, Rift or pawn-status screens), find which
native places the mod could plausibly extend: e.g. the pawn talk/command menu, the party/pawn status screen,
the Rift pawn list. For each: the classes/methods involved, how other mods have injected an option (if any), and
the risk (fragility across game updates, effort). Output: a ranked shortlist for the adopt/release UX decision.

## Answer

Findings: `docs/findings/research-m2-native-ui.md` on branch `research/m2-native-ui` (commit `2cd5b83`, never merged).
All classes exist in the dump; which screen each `ui0xxxxx` draws is inferred. Nothing tried in game.

- **Mod menu stays the one complete surface**: away pawns have no body in the world, so no in-world menu reaches them.
- **Best native spot**: the talk menu of a hired party pawn (Talk / Dismiss / Add to Favorites / Never mind), likely
  `app.PawnRentalNode` via `TalkEventPlayer.startPawnRentalNode` / `nextNode` / `newChoiceInfo`, drawn by `ui021601`.
  Guild Contracts is the pattern (rename `ListInfo.Msg` after `newChoiceInfo`, act before `nextNode`). Only four entries
  render, and the menu already has four, so reuse a slot (probably "Add to Favorites"). Risk medium-high (hooks every
  conversation), effort high; unknown whether the menu exists in the field or only at the Rift.
- **Release confirmation**: the game's own dialog, `GuiManager.requestDialog(String...)` + `getDialogState()`.
- **Fallback**: a button on the pause-menu Status page (`ui060601_01`) while a hired pawn's tab is selected; risk medium.
- **Ruled out for adopt/release**: Switch Pawn screen `ui041706` (maybe a later dismiss warning), Rift search `ui041401`
  (belongs to how an away pawn comes back), hotkey/overlay.
- No precedent mod adds an option to a pawn's menu. Four probe experiments for the UX ticket are listed in the findings.
