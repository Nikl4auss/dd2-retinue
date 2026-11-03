# API map

Game members relevant to the mod, verified against `il2cpp_dump.json` of 2026-11-03 unless marked otherwise.
"Seen in AO" = also used by Arisen's Own 1.3.2. Status: **verified-dump** (exists with this signature) or
**verified-game** (observed behaving as described in game).

## Party and pawns

| Member | Notes | Status |
|---|---|---|
| `app.PawnManager` (singleton) `._PartyPawnList : List<app.Pawn>` | live party, slot order | verified-game |
| `app.PawnManager._SavedPartyPawnList : List<app.CharacterID>` | party as saved | verified-game |
| `app.PawnManager.getPartyPawn(app.CharacterID, bool) : app.Pawn` | seen in AO | verified-dump |
| `app.PawnManager.hirePawn(app.Character, bool) : bool` | | verified-dump |
| `app.PawnManager.dismissPawn(app.CharacterID / app.Character / app.Pawn)` | | verified-dump |
| `app.PawnManager.onHirePawn / onDismissPawn : Action<app.Character>`, `onLost : Action<app.CharacterID>` | events | verified-dump |
| `app.Pawn.get_CachedCharacter() : app.Character`, `.get_PawnID() : PawnManager.PawnID` | | verified-game |
| `app.Pawn.MainPawnDataContext` (field) | set only for the main pawn | verified-game |
| `app.Character.get_CharaID()`, `.get_Context() : app.ContextHolder`, `.get_Human() : app.Human`, `.get_IsDead()` | | verified-game |
| `app.ContextHolder.Contexts : Dictionary<System.Type, ContextInfoBase>` → `.get_CurrentContext()` | read a context by type | verified-game |
| `app.ContextHolder.get_IsStore / get_IsRestore / get_UniqID / get_Level` | | verified-game |

## Hired-pawn checks (candidate hooks)

| Member | Notes | Status |
|---|---|---|
| `app.PawnUtil.isSubPawn(app.CharacterID)` / `(app.Character)` (static) | central check; broad effects unknown | verified-game (returns true for hired) |
| `app.PawnUtil.isMainPawn(app.CharacterID / app.Character / app.Pawn)` (static) | | verified-game |
| `app.ExpDispenser.isSubPawn(app.CharacterID)` | seen in AO; **never called by the game** during exp distribution, hooking it has no effect (0002) | verified-game |
| `app.ExpDispenser.checkLevelUp(CharacterID, HumanStatusContext, JobEnum, bool, DragonHermitContext)` | gated on the ID; rewriting it to the main pawn's levels the passed context; bool = show notification (0002) | verified-game |
| `app.ExpDispenser.addJobPoint(CharacterID, JobContext, int, bool)` | gated on the ID; with it rewritten, reaches `addJobPointInternal` (discipline + CulmativeExp) (0002) | verified-game |
| `app.ExpDispenser.dispLevelUpUI(CharacterID, int newLv, int oldLv)` | level-up notification; calls `GuiManager.reqLevelUp(id, oldLv, newLv)` (0002) | verified-game |
| `app.ItemIDUtil.isSubPawnDisableEquipItem(app.ItemIDEnum)` | items hired pawns cannot equip | verified-dump |
| `app.GUIBase.isSubpawnDisableEquipStorage(app.ItemDefine.StorageData)` | same, in menus | verified-dump |
| `app.ItemManager.returnSubPawnItems(app.CharacterID)` | returns items on dismissal | verified-dump |
| `app.GUIBase.CharaChangeJobGuildRef.ListInfo.IsSubPawn` | Vocation Guild list flag | verified-dump |

## Progression, vocation, equipment, name

| Member | Notes | Status |
|---|---|---|
| `app.Human.get_StatusContext() : HumanStatusContext` → `get_Level / get_Exp / set_* / levelup` | | verified-game (getters) |
| `app.Human.get_JobContext() : JobContext` → `get_Job / calcJobRank(JobEnum) / get_ConsumableExpProp` | | verified-game |
| `app.Human.get_JobChanger() : HumanJobChanger` → `requestChangeJob(JobEnum)` | | verified-dump |
| `app.ItemManager.setEquip(StorageData, Character, EquipData.SlotEnum, bool, bool)` / `removeEquip(...)` | | verified-dump |
| `app.Human.get_PawnDataContext() : PawnDataContext` → `_Name / _Nickname / setName(String)` | | verified-game (fields) |
| `app.GUIBase.getName(app.Character) : String` (static) | display name | verified-game |
| `app.PawnOwnerContext._Name / _Level / _Job / _OfflineID / _UserId / _SlotId` | creator info | verified-game |
| `app.SubPawnDataContext._HireTime / _RentalToken / _EquipStorage / ChangedEquipSlot` | rental state | verified-game (first three) |
