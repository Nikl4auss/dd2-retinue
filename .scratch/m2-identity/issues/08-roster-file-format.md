# What is the shape of the roster file and its validation?

Type: grilling
Status: resolved
Blocked by: 07

## Question

Decide the roster file (`reframework/data/Retinue/`): one file or alongside `config.json`, fields per entry
(identity key, present/away, anything for display), versioning, and validation/fallback for a malformed or
hand-edited file (following the `config.json` precedent from M1). Pure Lua and tested, per the roadmap.

## Answer

Resolved 2026-11-04 (grilling); every recommendation accepted.

- **File**: its own `reframework/data/Retinue/roster.json`, separate from `config.json` (settings vs. mod state).
  Where backups live is the backup ticket's call.
- **Shape**:
  ```json
  { "version": 1,
    "members": [
      { "offline_id": "1a2b…", "name": "Rook", "status": "present", "character_id": 12345 },
      { "offline_id": "…",     "name": "Elva", "status": "away" } ] }
  ```
  `members` is an array in adoption order (stable display). `offline_id`: the GUID as a canonical lowercase string.
  `status`: `"present"` | `"away"`, explicit. `character_id`: cache only, absent while away (REFramework's json drops
  `null`). `name`: display only. No timestamps or other fields; versioning allows them later.
- **Missing file**: empty roster; the file is created on the first adopt.
- **Damaged file, two levels**:
  - *Structural error* → roster **locked**: unparseable JSON, non-object top level, `members` not an array, a member
    without a valid `offline_id`, duplicate `offline_id`s, or more members than the cap. Locked means: no progression
    for anyone, Adopt and Release disabled with a reason, a warning in the menu and the log, and the file is never
    rewritten while locked. Fixed by hand-editing and *Reset scripts*. (Unlike `config.json`, defaults would let the
    next adopt overwrite the adopted pawns and orphan their backups.)
  - *Soft error* → field corrected with a warning: bad `name` → shown as "(unknown)"; bad `character_id` → empty
    cache; bad `status` → away (most conservative). All are re-observed from the game on load.
- **Higher `version`** → **read-only**: members that validate as v1 are used for progression; no writes; Adopt and
  Release disabled with a warning.
- **Unknown keys** are kept on rewrite, top level and per member (matched by `offline_id`), with the same
  `null` / `{}` caveat as `config.lua`. A released member leaves with its unknown keys.
- **Timing**: read once at script load; written immediately on every roster change (adopt, release, present↔away,
  Return) and when the cache (`character_id`, `name`) is refreshed. No `re.on_config_save`, no atomic write.
- **Global**, not per save; no save fingerprint for now. If "Roster vs. save drift" needs one, it adds it with
  `version: 2`.
  *Superseded (2026-11-04) by "How does the mod reconcile the roster with a save that disagrees with it?": one roster
  per save slot, `version` stays 1.*
- **Pure module** `src/autorun/Retinue/roster.lua` (no REFramework globals; I/O in `Retinue.lua`): `resolve`/`merge`
  plus the roster operations (adopt, release, mark away, return; the cap constant in one place) returning errors
  `full`, `already_adopted`, `locked`, `no_offline_id`; tested in `tests/roster_test.lua`.
