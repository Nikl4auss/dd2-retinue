# 0004 — Other installed mods on the exp path Retinue rewrites

Date: 2026-11-03 · Method: static reading of the installed scripts (none executed) · Ticket:
[06](../../.scratch/m1-progression/issues/06-other-mods-on-exp-path.md)

Question: which installed REFramework scripts hook or call the members Retinue M1 touches (ID rewrite to
`ch100000_00` in `ExpDispenser.checkLevelUp` / `addJobPoint`, swap-back in `dispLevelUpUI` /
`GuiManager.reqJobRankUp`, see [0002](0002-exp-hook-variants.md), [0003](0003-notification-swap-back.md)), and
does any of them see the rewritten ID, change the numbers Retinue relies on, or already lift the hired-pawn gate?

## Method

All 617 files under `reframework/autorun/` (top level and every subfolder) were searched with `grep -rnI` for:
`ExpDispenser`, `checkLevelUp`, `addJobPoint`, `addExp`, `JobPoint`, `CulmativeExp`, `ConsumableExp`,
`reqLevelUp`, `reqJobRankUp`, `setLevelUp`, `dispLevelUpUI`, `LevelUp`, `Dispenser`, `JobRank`, `isSubPawn`,
`isMainPawn`, `PawnUtil`, `SubPawn`, `PawnPartyCombatInfo`, `HumanStatusContext`, `StatusContext`, `JobContext`,
`get_Exp` / `set_Exp` / `Exp`, `Level`, plus every `find_type_definition(...)` / `get_method(...)` naming a Job,
Status, Exp, Pawn, Skill, Level or Human type, and every `get_methods()` loop (hooks installed by name at runtime).
Each hit was read in context. The three native plugins in `reframework/plugins/` (`DD2MethodLibrary.dll`,
`DD2PakBridge.dll`, `reframework-d2d.dll`) were checked with `strings` (ASCII and UTF-16) for the same member
names: no hits. Data-only content (`reframework/data/usercontent`, Content Editor) has no exp tables.

## Scripts scanned

Top level: `aaaNickCore.lua`, `AdditionalPawnCommands.lua`, `Bestiary.lua`, `Bestiary_ApexAddon.lua`,
`Better Quick Use.lua`, `BetterBetterItemDescription.lua`, `content_editor.lua`, `devtools.lua`, `Dullahan.lua`,
`editor_ai.lua`, `editor_chests.lua`, `editor_enemy.lua`, `editor_events.lua`, `editor_human_params.lua`,
`editor_items.lua`, `editor_npc.lua`, `editor_quest.lua`, `editor_shops.lua`, `editor_sound_viewer.lua`,
`editor_weathers.lua`, `GPO.lua`, `guild_contracts.lua`, `!LeovvayGore_first.lua`, `LeovvayGore.lua`,
`MenuPerformanceBoost.lua`, `_NicksDevtools.lua`, `PartyBox.lua`, `QuestCore_Menu.lua`, `QuestCore_Template.lua`,
`reframework-d2d.lua`, `RemoveCameraEffects.lua`, `SimpleDifficultyTweaks.lua`, `SkillCreator.lua`, `UDD2P.lua`,
`WarfarerArsenal.lua`.

Subfolders: `Bestiary/` (incl. `Enemies/`, `EnemyVariants/`, `MovesetHandler/`, `Utils/`), `Bestiary_ApexAddon/`,
`content_editor/`, `Dullahan/`, `editors/`, `GPO/`, `GuildContracts/`, `Hotkeys/`, `LeovvayGore/`, `_NickCore/`,
`NicksDevtools/`, `QuestCore/`, `_SharedCore/`, `SimpleDifficultyTweaks/`, `SkillCreator/`, `UDD2P/`, `_XYZApi/`.

`Arisens Own/` exists but is **empty** (Arisen's Own is uninstalled, as in 0001). No Retinue script or symlink is
installed at the moment (the experiment tool is not in `autorun/`), so nothing had to be excluded.

## Hits

The game's call order (0002): `addExpAndJobPoint(id, exp, chara, damageInfo)` → `addExpAndJobPoint(id, exp,
jobPoint, chara)` → `checkLevelUp` / `addJobPoint` → `addJobPointInternal`. "Upstream" below means before
Retinue's rewrite: such a hook always sees the **real** CharacterID.

| File:line | Member | What it does | Sees rewritten ID? | Changes Retinue's numbers? |
|---|---|---|---|---|
| `SimpleDifficultyTweaks/exp.lua:6-37` | hook, `addExpAndJobPoint(CharacterID, Int32, Int32, Character)` (inner overload) | Pre: if the ID is the hard-coded player `2891076981` or main pawn `2283028347` (lines 3-4, 11), multiplies exp by `expMult` and jobPoint by `dcpMult` (clamped to 0..10×). Post: player-only `set_Exp(get_Exp()-1)` when `expMult == 0` | No (upstream, real ID) | Not for hired pawns: they are filtered out by ID. With multipliers ≠ 1, the main pawn and player gain at a different rate than hired pawns. Active preset `SimpleDifficultyPresets/Default.json`: both multipliers **1.0** |
| `Bestiary/VariantHandler.lua:250-262` | hook, `addExpAndJobPoint(CharacterID, Int32, Character, DamageInfo)` (outer, combat) | Multiplies exp by the killed enemy's variant `expMult` (default 2.5; values 1.1-2.0 in `Bestiary_ApexAddon/VariantData.lua`) | No (upstream; keyed on the enemy, ignores the recipient ID) | Exp only, for every recipient alike (player, main pawn, hired). JobPoint untouched |
| `Bestiary/ConditionalStatTweaks.lua:241-274` | hook, same outer overload | Multiplies exp by the enemy's night / Unmoored World / Norgan `expMult`, if configured | No (upstream, enemy-keyed) | Exp only, all recipients alike |
| `UDD2P/SphinxAndMedusaFix.lua:9, 96-110` | **call**, inner `addExpAndJobPoint(id, 10000, 233, character)` | When the Sphinx is killed outside her quest, grants 10 000 exp and 233 jobPoint to every character from `NickCore.object.get_party()` (player + `PawnManager.PawnCharacterList`, i.e. hired pawns too), from a timer, not nested in any exp call | Not a hook. Its grants pass through Retinue's leaf hooks like any other source | No. Hired pawns now get this reward's level/discipline (intended). SDT's hook also applies to it for player/main pawn |
| `SkillCreator.lua:19, 93, 131` | **call**, `addJobPointInternal(playerID, nil, jobContext, dcp, false)` | Refunds discipline for skills it removes, **player only**, from a UI action | Not a hook. Bypasses `addJobPoint`, so Retinue's rewrite never sees it. May reach `GuiManager.reqJobRankUp` with the **player's** ID while no rewritten call is open | No. Relevant only to the swap-back guard (see below) |
| `WarfarerArsenal.lua:5617-5627` | hook, `HumanStatusContext.calcMaxHp` / `calcMaxStamina` | Replaces the vocation argument with the weapon's vocation | n/a; returns early unless `this` is the **player's** `StatusContext` (address check, line 5622) | No. A hired pawn's level-up recalculation is untouched |
| `WarfarerArsenal.lua:360`, `aaaNickCore.lua:157,194` | read, `get_JobContext` / `CurrentJob` | Reads the player's current vocation | No | No |
| `PartyBox.lua:457-458` | read, `Character.get_Context().get_Level()` | Shows "Lv.N" on the party HUD | No | No (read-only; useful to see a hired pawn's new level in game) |

No hits at all for: `checkLevelUp`, `addJobPoint` (the public one), `dispLevelUpUI`, `GuiManager.reqLevelUp`,
`GuiManager.reqJobRankUp`, `PawnPartyCombatInfo.setLevelUp`, `ExpDispenser.isSubPawn`, `PawnUtil.isSubPawn` /
`isMainPawn`, `CulmativeExp`, `ConsumableExpProp`, `calcJobRank`, `HumanStatusContext.set_Level` / `levelup`.
The runtime `get_methods()` loops that hook `GuiManager` methods by name pick other methods only
(`QuestCore/core.lua:1257` `requestQuestNotice`; `WarfarerArsenal.lua:2045` `requestJobGuildMenu2`;
`MenuPerformanceBoost.lua` shop requests; `PartyBox.lua:705` `requestGUIPause`; several `OnChangeSceneType`).

## Conflicts and severity

1. **No mod hooks any member Retinue rewrites or swaps back.** Nothing downstream of the rewrite can see
   `ch100000_00` in place of a hired pawn. Severity: **none**.
2. **No mod already lifts the hired-pawn gate.** No `isSubPawn`, `checkLevelUp` or `addJobPoint` hook; Arisen's
   Own (which hooked `ExpDispenser.isSubPawn`, a no-op per 0002) is not installed. No double-application risk.
   Severity: **none**.
3. **SimpleDifficultyTweaks applies its EXP/DCP multipliers to the player and main pawn only**, by hard-coded
   ID, upstream of Retinue. With the user's current preset (1.0 / 1.0) there is no effect. If the user raises or
   lowers them, adopted pawns progress at the vanilla rate while the main pawn does not. Retinue's rewrite does
   not change this, because SDT reads the ID before the rewrite. Severity: **low, cosmetic/balance**; works as
   designed for SDT, but a user may expect adopted pawns to follow it.
4. **Bestiary (+ Apex Addon) multiplies combat exp per enemy for all recipients.** Hired pawns get the same
   scaled exp as everyone, so Retinue's levels follow it. Severity: **none** (harmless interaction).
5. **UDD2P's Sphinx reward calls `addExpAndJobPoint` for hired pawns.** With Retinue on, they level from it like
   from any other grant (a large one: up to several levels, one notification, as in 0003). Severity: **none**;
   confirms that "hook the leaves" covers mod-originated grants too.
6. **SkillCreator calls `addJobPointInternal` directly for the player.** If it raises the player's rank, the
   resulting `reqJobRankUp` carries the player's ID outside any rewritten call. A swap-back that is not strictly
   scoped (e.g. a stale "pending real ID" left after an error) would rename that notification to a hired pawn.
   Severity: **low**, only under a Retinue bug; the guard below prevents it.

Hook order between mods does not matter here: the only shared hooked methods (`addExpAndJobPoint` overloads) are
not hooked by Retinue, and all their effects happen before `checkLevelUp` / `addJobPoint` run.

## What the M1 spec must state

1. **Keep the rewrite on the leaves only.** Retinue must not hook or rewrite the ID in either
   `addExpAndJobPoint` overload. Moving the rewrite upstream would make SimpleDifficultyTweaks treat hired pawns
   as the main pawn (applying its multipliers to them) and would hide the real ID from Bestiary's and SDT's hooks.
2. **Scope the swap-back strictly.** In `dispLevelUpUI` and `GuiManager.reqJobRankUp`, replace the ID only when it
   equals `ch100000_00` **and** a rewritten `checkLevelUp` / `addJobPoint` call is currently open on this thread;
   set the pending real ID in the pre-hook and clear it in the post-hook (and reset it at the start of every
   `checkLevelUp` / `addJobPoint` pre-hook). Calls with any other ID (player via SkillCreator, the main pawn's own
   level-ups) pass through untouched.
3. **Exp amounts are taken as the game passes them.** Retinue applies no multiplier of its own (debug multipliers
   are experiment-only); exp and jobPoint reaching the leaves may already be scaled by Bestiary (all recipients)
   and SimpleDifficultyTweaks (player and main pawn only). Mirroring SDT's multipliers onto adopted pawns is out
   of scope for M1; note it as a known difference.
4. **Mod-originated grants are covered.** Any script calling `addExpAndJobPoint` for a hired pawn (UDD2P's Sphinx
   reward) levels it through the same path; no special handling.
5. **Compatibility note for users:** no conflict with the installed set; do not run Retinue together with another
   mod that lifts the hired-pawn exp gate (e.g. a reinstalled Arisen's Own variant that hooks `checkLevelUp` or
   `addJobPoint`); re-run this scan when mods are added.
6. **In-game checklist addition:** one SimpleDifficultyTweaks check is enough to confirm item 3 if the user ever
   sets EXP mult ≠ 1 (main pawn scaled, adopted pawn not).

## Limits

Static reading only; no script was run. Assumed, not tested: REFramework `sdk.hook` detours also fire for calls
made from Lua with `method:call` (UDD2P, SkillCreator), which is how the hooks are installed (native detours).
Native plugins were checked by string search only.
