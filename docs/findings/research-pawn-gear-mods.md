# Research: how other DD2 mods handle a hired pawn's gear and items across dismiss, lost and re-hire

Date: 2026-11-08 · Scope: research only, no game run, no mod executed · Input for: M2 (gear warning, backup) and
[roadmap](../roadmap.md) M4 (equipment)

Question: which mods keep or restore a hired (or owned) pawn's equipment and carried items on dismiss, lost and
re-hire; whether any returns *equipment* to the player; which pitfalls they report; which game API they use.
Baseline: in vanilla, `dismissPawn` calls `ItemManager.returnSubPawnItems(CharacterID)`, which returns carried items
but not equipment, and a re-hired pawn comes back with regenerated gear ([0006](0006-m2-dismiss-lost-rehire.md)).

## Sources and how they are cited

- **Nexus pages.** nexusmods.com returns 403 to WebFetch. Each mod's description, version, dates and per-file
  changelogs were read through Nexus's public GraphQL API (`https://api.nexusmods.com/v2/graphql`,
  `legacyModsByDomain` and `modFiles`), which returns the same text the mod page shows. The links below point to the
  mod pages. Comment and bug tabs are not exposed by the API and were not read.
- **Mod source.** Nexus archives need a logged-in download, so the code of Arisen's Company, Pawn Fashion Dogma,
  The Pawn Controller and Unlimited Pawns was **not** read. What those mods do is the author's own statement; *how*
  they do it is inferred. Read in source: Arisen's Own 1.3.2 (installer copy in the game folder,
  `…/Dragon Dogma 2/Arisens Own-Setup/reframework/autorun/Arisens Own/`, cited `AO <file>:<line>`) and
  [Precyse/Tether](https://github.com/Precyse/Tether) (GitHub).
- **Dump.** `il2cpp_dump.json` of 2026-11-03 via `tools/dump/sig.py`, cited `dump: Type.member`. It gives
  signatures only, no method bodies.
- **Search.** GitHub code search for `returnSubPawnItems`, `isSubPawnDisableEquipItem`, `OnlineRentalEquipStorageData`,
  `dismissPawn`, `getStorageDict` and `SubPawnDataContext` found no DD2 mod that handles hired-pawn gear. The only DD2
  hits were [kagenocookie/dd2-content-editor](https://github.com/kagenocookie/dd2-content-editor) (a type
  definition list), [Goosterhof/riftstone](https://github.com/Goosterhof/riftstone) (a mod manager) and Tether. Nexus
  was searched by name for `pawn`, `gear`, `equip`, `support`, `hire`, `item`, `inventory`, `rift` and `companion`
  (88 "pawn" mods). Each candidate's description was then read.

Labels: **[V-src]** read in source code. **[V-page]** stated on the mod's own page or changelog by its author (what
the author says the mod does, not how). **[V-dump]** member exists with this signature. **[I]** inferred.

## 1. Mods that keep or restore hired-pawn gear

| Mod (version, date) | What it does with gear | Dismiss / lost / re-hire | Mechanism |
|---|---|---|---|
| [Arisen's Company](https://www.nexusmods.com/dragonsdogma2/mods/1954) by Tyad (1.2, 2026-11-07) | Gear you give is "protected": when replaced or removed it goes into the pawn's own bag, enhancements included; no "items will be returned to its master" message; also at the armorer and on vocation change [V-page] | 1.2: "when a pawn leaves (dismissed, Dragonsplague, lost, NG+), everything you gave goes back to your inventory. Their original gear goes back to their creator, as in the base game" [V-page]. Progress, not gear, comes back on re-hire (NG+ "Restore" button) [V-page] | Unknown (code not read). Tracking which items the player gave, and refunding them at departure, is [I]. It stores data in `reframework/data/ArisensCompany` [V-page] |
| [Pawn Fashion Dogma - Keep Your Gear](https://www.nexusmods.com/dragonsdogma2/mods/1968) by Lilyhunte (3.1, 2026-10-30) | When you equip an item on a hired pawn, a "perfect copy" is refunded to your inventory at once, with upgrades, smithy stats and Norgan appraisal rolls [V-page] | Not handled: the original stays on the pawn and leaves with it; you keep the copy [V-page, I] | "intercepts the gifting process" after the game's warning prompt [V-page]. This is likely a hook at or after `setEquip` that calls `getItem` with the item's enhance/ability params [I] |
| [The Pawn Controller](https://www.nexusmods.com/dragonsdogma2/mods/1223) by Evo (2.2.0, 2026-10-16) | Sets any item in any slot of a hired pawn, with enhancement, Dragonforge and appraisal rolls; "Restore" puts the original back [V-page] | "Hired pawns don't keep gear that gets replaced" [V-page]. 2.2.0: a pawn's *settings* (gear overrides included) come back when the same pawn is re-hired after drowning, death or dismissal; "settings stick to the pawn, not the slot" [V-page] | Mod-side override list keyed per pawn and reapplied on hire [V-page]. "Some changes are permanent and get written to your save" [V-page] |
| [Unlimited Pawns](https://www.nexusmods.com/dragonsdogma2/mods/1691) by Ridog8 (1.04, 2026-11-01) | Extra hires get gear via the normal equipment menu and keep it in the mod's own JSON. 1.04 adds "retrieve buttons to take back items/equipment" [V-page] | Its extra hires are not in the save: "the pawns are using that data and not apart of saved data" [V-page]. Giving gear away and then saving "will stay given away" [V-page] | Gear list stored in `reframework/data/UnlimitedPawns/ExtraHires/*.json`; needs the C# API [V-page] |
| [Arisen's Own](https://www.nexusmods.com/dragonsdogma2/mods/2031) by CorsMods (1.3.2, 2026-10-23) | Owned pawns are main pawns, not rentals. It grants and equips their starter and restored gear itself [V-src] | Dismiss: waits until the pawn's `StorageDict` and `EquipDict` entries are gone, then commits the removal (`removal_service.lua:37-51`) [V-src]. It never hooks `returnSubPawnItems` (no hit in the source) [V-src]. Restore: a one-off journal for one hard-coded pawn ("Greya", `greya_restore.lua:22-25`) [V-src] | `ItemManager.getItem(itemId, num, CharacterID)`, then `StorageMasterData.set_IsNew`, then `ItemManager.setEquip(storageData, chara, slot, true, false)` (`inventory_restore.lua:93-101`, `inventory_repair.lua:112-125`) [V-src] |

Mods looked at that do **not** handle gear across departure: [Extra Pawn Guild](https://www.nexusmods.com/dragonsdogma2/mods/2026)
says "dismissing a pawn loses it, as in the base game", and it writes progress into the save [V-page].
[Hidden Extra Pawns V2](https://www.nexusmods.com/dragonsdogma2/mods/1975) and
[More Pawns V4](https://www.nexusmods.com/dragonsdogma2/mods/1582) handle party size only; HEP keeps shop and
equipment menus to the normal party of 3 to avoid a shop crash [V-page]. Hired Pawn Editor
([1130](https://www.nexusmods.com/dragonsdogma2/mods/1130), [2299](https://www.nexusmods.com/dragonsdogma2/mods/2299))
and [Hired Pawn Manager](https://www.nexusmods.com/dragonsdogma2/mods/2059) cover appearance and skills only.
No "main pawn as support pawn" mod was found.

## 2. Does any mod return *equipment* to the player on dismiss?

**Yes, one: Arisen's Company 1.2**, and only for items the player gave. The creator's original gear "goes back to
their creator, as in the base game" [V-page]. Its changelog dates this to 2026-11-07, one day before this research,
and the code was not read, so the claim is the author's alone. Pawn Fashion Dogma reaches the same end by
duplicating the item at equip time, not at dismiss [V-page]. Unlimited Pawns has manual "retrieve" buttons for its own
extra hires [V-page]. No mod restores a pawn's *equipment* on re-hire from the Rift except The Pawn Controller, which
re-applies its own per-pawn overrides [V-page]. AO restores gear only for its own main-pawn-ID pawns [V-src].

## 3. Reported pitfalls

- **Duplication.** Arisen's Company 1.2: gear "never lost or duplicated anymore" [V-page], so earlier versions
  lost or duplicated items (1.0 already claimed "protected gear") [I]. Pawn Fashion Dogma 2.1 fixed "a rare bug where
  equipping items from the Inn storage could occasionally cause a refund of unrelated items", by "a strict Character ID
  check" [V-page]. A refund keyed on the wrong owner or event duplicates items.
- **Save state and rollback.** Pawn Fashion Dogma asks for a manual save before gifting, "if a future game patch or mod
  conflict ever breaks the script hook" [V-page]. Arisen's Company ties progress to saves ("load an older save and they
  go back to that moment") [V-page]. Nothing says how its gear refund behaves when the player reloads after a dismiss
  [I: a refund done before the reload point would duplicate the item]. AO blocks saving during removal and restore, and
  until it verifies native records after a load (`removal_service.lua:31-33`; [page](https://www.nexusmods.com/dragonsdogma2/mods/2031)) [V-src, V-page].
- **Owned-vs-rental bookkeeping.** AO hooks `SubPawnDataContext.changeEquipSlot`, `setEquipStorage` and
  `setRentalToken` and **skips them** for its owned pawns. Its comment says this excludes them "from rental
  equipment/token updates", and it clears `ChangedEquipSlot` with `resetChangedEquipSlot`
  (`owned_bookkeeping.lua:1-2, 38-52`) [V-src]. It also refuses a pawn with an `_EquipStorage`
  ("Online rental equipment present", `owned_bookkeeping.lua:29`; `save_roster.lua:55`) [V-src]. So equipping a hired
  pawn records the changed slots in its `SubPawnDataContext`. That record probably feeds the rental result sent back
  to the creator [I].
- **Online pawn validation and rental rewards.** [Pawn Share Settings](https://www.nexusmods.com/dragonsdogma2/mods/1057)
  (kagenocookie) lists the client-side `app.PawnRentalValidator` checks on received pawns:
  `isValidationCanEquip` (gear the vocation can't use), `isValidationEquipEqualWeponAndMeta`,
  `isValidationRewardItem` (gift items: blacklist, `_RewardEquipItemMaxNum` for weapon/armor, a gold-value limit) and
  `validationPresentItem` [V-page, code excerpt on the page]. Pawns that fail are not shown to players without the mod
  [V-page]. Lifting equip restrictions is safe locally. The risk is the data that leaves the game: uploads and rental
  results/gifts [I]. The Pawn Controller's "Validate Pawn" runs "the game's own upload check" for this reason [V-page].
- **Mod conflicts.** Arisen's Company: "Mods that also change support pawns (XP, equipment, guild, barber) may
  conflict"; More Pawns V4 is incompatible as of 1.1 [V-page]. Extra Pawn Guild warns that it and The Pawn Controller
  or Arisen's Company "will fight each other" over levels [V-page]. Retinue overlaps Arisen's Company almost entirely
  [I].
- **Save corruption.** No mod page reports save corruption from gear handling. AO's page warns about uninstalling with
  owned pawns still registered, which is about its main-pawn records, not gear [V-page].

## 4. Game API they use, against [api-map.md](api-map.md)

| Member | Used by | In api-map? |
|---|---|---|
| `ItemManager.returnSubPawnItems(CharacterID)` | vanilla dismiss and lost (0006). No mod found hooks it | yes |
| `ItemManager.setEquip(StorageData, Character, EquipData.SlotEnum, bool, bool)` | AO, called as `(param, chara, slot, true, false)` [V-src] | yes |
| `ItemManager.removeEquip(StorageData, Character, bool, bool)` | none seen | yes |
| `ItemManager.getItem(Int32 itemId, Int32 num, CharacterID)`; overloads with `ItemDefine.GetItemOption` and with `Character` [V-dump] | AO grants an item to a given character's storage [V-src] | **new** |
| `ItemDefine.GetItemOption` (struct): `EnhanceInternal`, `AbilityInternal`, `ExtensionValue`, `IsSubPawnEquiped`, `IsNewMark`, `IsNotice`, `setEquipmentOption(EnhanceParam, EquipmentAbilityParam, Int32)` [V-dump] | the likely way to grant a copy with enhancement and appraisal rolls (Pawn Fashion Dogma's "perfect copy") [I] | **new** |
| `ItemManager.StorageDict : Dictionary<UInt32, List<ItemManager.StorageMasterData>>` + `StorageLocker`; `EquipDict : Dictionary<UInt32, EquipData>` (`.Equips` array) + `EquipLocker` (`SimpleReaderWriterLock`, `readLock` / `readUnlock`) [V-dump] | AO reads a pawn's carried items and equipped slots by CharacterID under the lock (`inventory_readonly.lua:48-80`) [V-src] | **new** |
| `ItemManager.getStorageDict() : Dictionary<UInt32, List<ItemDefine.StorageData>>` [V-dump] | none seen | **new** |
| `ItemManager.StorageMasterData._Param : ItemDefine.StorageData`, `set_IsNew` [V-dump] | AO (`inventory_restore.lua:56-66, 100`) [V-src] | **new** |
| `ItemDefine.StorageData` fields `_ItemId, _Num, _CharaId, _StorageId, _IsEquipped, _EquipSlot, _Enhance, _Ability, _ExtensionValue, _AppearanceItemData`; `canEquip(CharacterID, bool)` [V-dump] | AO checks every field it restores and admits only unenhanced, unappraised items ("enhancement/appearance not admitted", `inventory_restore.lua:4-10, 26-29`) [V-src] | **new** |
| `ItemManager.onEquipOffAction : Action<StorageData, SlotEnum, CharacterID>`, `onPassStorageAction : Action<Int32, Int32, CharacterID, CharacterID>`, `onSubStorageAction`; `ItemManager.onHirePawn(Character)` [V-dump] | none seen; candidate events for tracking gifts [I] | **new** |
| `ItemManager.isOfficialPawnNotEquipItem(ItemCommonParam)` / `…Category(ItemEquipCategory)` / `…Slot(SlotEnum)` [V-dump] | probably part of the restriction Arisen's Company 1.1 lifts [I] | **new** (api-map lists only `ItemIDUtil.isSubPawnDisableEquipItem`, `GUIBase.isSubpawnDisableEquipStorage`) |
| `SubPawnDataContext.changeEquipSlot(SlotEnum)`, `resetChangedEquipSlot()`, `getChangedSlotList()`, `setEquipStorage(OnlineRentalEquipStorageData)`, `setRentalToken(Guid)`; field `ChangedEquipSlot : PawnDefine.EquipSlot` [V-dump] | AO blocks the three setters for owned pawns [V-src] | fields yes; **methods new** |
| `OnlineRentalEquipStorageData._Equips : EquipStorageData[]` (`ItemID`, `EnhanceNum`, `Type0-2`, `Slot1-4`, `Physical/Magic/Blow/WeightParam`, `IsAppraised`) [V-dump] | AO refuses pawns that carry it [V-src]; it looks like the creator's online gear set for a rented pawn [I] | **new** (api-map has `_EquipStorage` only) |
| `app.PawnRentalValidator.isValidationCanEquip / isValidationRewardItem / validationPresentItem / isValidationEquipEqualWeponAndMeta` | Pawn Share Settings disables them [V-page] | **new** |
| `List<ItemManager.ItemStorageBackup>` in the `ItemManager` save section | Tether reads and splices item records per owner in the save data ([`calls.h`](https://github.com/Precyse/Tether/blob/HEAD/adapters/dd2/src/calls.h) L203-209, [`profile.cpp`](https://github.com/Precyse/Tether/blob/HEAD/adapters/dd2/src/profile.cpp) L108-137) [V-src] | **new** (save injection, ruled out by [ADR 0001](../adr/0001-runtime-lift-not-save-injection.md)) |

The `returnSubPawnItems` closure `<>c__DisplayClass1520_0.<returnSubPawnItems>b__(ItemManager.DecayData)` filters
decay data by `chara_id` [V-dump]. So the call also clears the pawn's item-decay entries [I].

## Implications for Retinue

**M2 (now): keep the warning, add nothing.** The spec already records equipped item IDs and warns that gear given to
a pawn is lost ([spec](../../.scratch/m2-identity/spec.md)). No primary source shows a safe, tested refund path. The one
mod that claims it (Arisen's Company 1.2) shipped it a day ago, and its code is unread. Risk: none.

**M2 (optional): a better backup for M4.** At the existing backup points, read the pawn's `EquipDict` slots and
`StorageDict` entries under their locks, as AO does. Store item ID, count, slot, `_Enhance`, `_Ability` and
`_ExtensionValue`, not only item IDs. This is read-only and needs no new hooks. Risk: lock misuse; take the
read-lock in a `pcall` and always release it, as AO does.

**M4 option A: refund the player's gifts at departure** (Arisen's Company's model). Track which items the player gave
(hook `setEquip` / `onPassStorageAction` for adopted pawns, keyed on CharacterID). On `dismissPawn` pre, and while the
pawn is in the party for lost, since lost has no single hook (0006), grant them back to the Arisen with
`getItem(id, num, playerID, GetItemOption)`. Risks: (1) duplication if the grant happens and the player reloads a save
from before the dismiss, or if the item also returns some other way. Pawn Fashion Dogma's "refund of unrelated items"
bug shows how easily the owner check goes wrong. (2) Lost has no reliable event, so the refund may fire late or twice.
(3) Copy fidelity: enhancement and appraisal must go through `GetItemOption`. (4) The creator may still receive the
gear through rental results [I].

**M4 option B: re-equip the backup on re-hire** (AO's grant-then-equip model). On `hirePawn` post for a roster pawn,
`getItem(id, num, newCharacterID)` then `setEquip(param, chara, slot, true, false)`. Risks: the CharacterID is new and
the record is not queryable until a save (0006), so wait until the pawn is ready. The regenerated creator gear must be
removed or kept; removing it may "return it to its master". Combined with option A this duplicates: choose one owner
for each item. The changed slots are recorded in `SubPawnDataContext.ChangedEquipSlot`, which may reach the creator
[I]. AO's fix is to block `changeEquipSlot` / `setEquipStorage` / `setRentalToken`, but its pawns are main-pawn IDs.
Blocking them on a real rental could break the creator's rental result or the Rift reward [I].

**The roadmap line "no `returnSubPawnItems` for adopted pawns" probably does not work as written.** On dismiss the
game deletes the pawn's record and its storage entries go away (AO waits for exactly this), and a re-hire gets a new
CharacterID (0006). Skipping the return would most likely *lose* the carried items rather than keep them [I]. "Items
stay with the pawn" needs mod-side storage plus option B, or option A. Test it before building on it: skip
`returnSubPawnItems` once on a throwaway save and check `StorageDict` for the old ID after dismiss and after re-hire.

**Lifting equip restrictions** (Arisen's Company 1.1 does it, with a toggle) touches `ItemIDUtil.isSubPawnDisableEquipItem`,
`GUIBase.isSubpawnDisableEquipStorage` and probably `ItemManager.isOfficialPawnNotEquip*`. Local risk is low. Gear a
vocation can't use fails `PawnRentalValidator.isValidationCanEquip` on other players' clients [V-page]. Since adopted
pawns are other players' rentals, what the creator receives back is the open question [I]. Keep it behind a toggle.

**Compatibility.** Arisen's Company overlaps Retinue in progression, gear, guild and lost protection. Running both
would double-handle the same hooks. Detect it (`reframework/autorun/ArisensCompany.lua`) and warn [I].
