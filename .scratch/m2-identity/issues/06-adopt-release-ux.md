# How should adopt and release look and feel?

Type: prototype
Status: claimed
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
(can Adopt/Release be added instead of replacing an existing option?). Awaiting the in-game run.
