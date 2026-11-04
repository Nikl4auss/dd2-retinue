# What identifies an adopted pawn across dismiss and re-hire?

Type: grilling
Status: resolved
Blocked by: 04

## Question

Given the experiment results: what does the roster key an adopted pawn by (`_OfflineID`, CharacterID, or both),
and how does the mod recognise an away pawn coming back? What happens when the key is ambiguous or missing?

## Answer

Resolved 2026-11-04 (grilling). Evidence: findings 0006 (re-hire keeps the OfflineID, gets a new non-deterministic
CharacterID).

- **Key = `_OfflineID` alone.** The roster also stores the pawn's current CharacterID as a cache ("where it is in this
  save"): refreshed on load and on return, `nil` while away; never used as identity.
- **Return is recognised** on `PawnManager.hirePawn` (post) when the hired pawn's OfflineID matches an away roster
  member, and by a party scan on save load, both matching by OfflineID. The member becomes present, its CharacterID
  cache is set, and restore is triggered (what and when: backup/restore tickets).
- **Any route counts**: a hire with a roster OfflineID is the return, whether from the "previously hired" list, the
  regular Rift list or a pawn met in the world. Unhired pawns in the world are ignored.
- **No OfflineID** (nil, all-zero GUID, or owner not `CAPCOM`): not adoptable; "Adopt" is not offered or is refused with
  a reason. No surrogate key is ever invented.
- **Ambiguity** (two party pawns with the same OfflineID; should not happen): that roster member is treated as
  ambiguous: no progression, no restore, a warning in the log. Never guess. Reconciliation belongs to roster-vs-save drift.
- **Display data**: the roster stores the pawn's name (refreshed while present), for display only.
- Glossary: `CONTEXT.md` updated (Offline ID verified as the roster key, CharacterID changes on re-hire, new term
  **Return**).
- To verify in the restore experiment: that `PawnOwnerContext._OfflineID` is readable in `hirePawn` post, before the
  record becomes queryable (findings 0006: record lookups only turn true after a save).
